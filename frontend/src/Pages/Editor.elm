module Pages.Editor exposing (Model, Msg, Params, page)

import Animation exposing (Timeline)
import Api.Backend
import Api.Ports
import Arrow exposing (Arrow)
import Browser.Events
import CastingDeco
import Element exposing (Element, centerX, fill, height, padding, spacing, width)
import Element.Background as Background
import Element.Font as Font
import Element.Input as Input
import EventsCustom exposing (BoardMousePosition)
import File.Download
import FontAwesome.Icon exposing (Icon, viewIcon)
import FontAwesome.Regular as Regular
import FontAwesome.Solid as Solid
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import Pieces
import Pivot as P exposing (Pivot)
import PositionView exposing (BoardDecoration(..), DragPieceData, DragState, DraggingPieces(..), Highlight(..), OpaqueRenderData, coordinateOfTile, nextHighlight)
import Result.Extra as Result
import Sako exposing (Piece, Tile(..))
import SaveState exposing (SaveState(..), saveStateId, saveStateModify, saveStateStored)
import Shared
import Spa.Document exposing (Document)
import Spa.Page as Page exposing (Page)
import Spa.Url as Url exposing (Url)
import Svg.Attributes as SvgA
import Svg.Custom as Svg
import Time exposing (Posix)


page : Page Params Model Msg
page =
    Page.application
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        , save = save
        , load = load
        }



-- INIT


type alias Params =
    ()


type alias Model =
    { saveState : SaveState
    , game : Pivot Sako.Position
    , preview : Maybe Sako.Position
    , timeline : Timeline OpaqueRenderData
    , drag : DragState
    , windowSize : ( Int, Int )
    , userPaste : String
    , pasteParsed : PositionParseResult
    , analysis : Maybe AnalysisReport
    , smartTool : SmartToolModel
    , showExportOptions : Bool
    , castingDeco : CastingDeco.Model
    , inputMode : Maybe CastingDeco.InputMode
    , colorScheme : Pieces.ColorScheme
    }


type PositionParseResult
    = NoInput
    | ParseError String
    | ParseSuccess Sako.Position


type alias KeyStroke =
    { key : String
    , ctrlKey : Bool
    , altKey : Bool
    }


type alias DownloadRequest =
    { svgNode : String
    , outputWidth : Int
    , outputHeight : Int
    }


encodeDownloadRequest : DownloadRequest -> Encode.Value
encodeDownloadRequest record =
    Encode.object
        [ ( "svgNode", Encode.string <| record.svgNode )
        , ( "outputWidth", Encode.int <| record.outputWidth )
        , ( "outputHeight", Encode.int <| record.outputHeight )
        ]


init : Shared.Model -> Url Params -> ( Model, Cmd Msg )
init shared { params } =
    ( initialEditor shared.windowSize, Cmd.none )


initialEditor : ( Int, Int ) -> Model
initialEditor windowSize =
    { saveState = SaveNotRequired
    , game = P.singleton Sako.initialPosition
    , preview = Nothing
    , timeline = Animation.init (PositionView.renderStatic Sako.initialPosition)
    , drag = Nothing
    , windowSize = windowSize
    , userPaste = ""
    , pasteParsed = NoInput
    , analysis = Nothing
    , smartTool = initSmartTool
    , showExportOptions = Basics.False
    , castingDeco = CastingDeco.initModel
    , inputMode = Nothing
    , colorScheme = Pieces.defaultColorScheme
    }



-- UPDATE


type Msg
    = EditorMsgNoOp
    | MouseDown BoardMousePosition
    | MouseMove BoardMousePosition
    | MouseUp BoardMousePosition
    | Undo
    | Redo
    | Reset Sako.Position
    | KeyUp KeyStroke
    | DownloadSvg
    | DownloadPng
    | SvgReadyForDownload String
    | UpdateUserPaste String
    | UseUserPaste Sako.Position
    | SavePosition Sako.Position SaveState
    | PositionSaveSuccess SavePositionDone
    | RequestRandomPosition
    | GotRandomPosition Sako.Position
    | RequestAnalysePosition Sako.Position
    | GotAnalysePosition AnalysisReport
    | ToolAddPiece Sako.Color Sako.Type
    | SetExportOptionsVisible Bool
    | SetInputModeEditor (Maybe CastingDeco.InputMode)
    | ClearDecoTilesEditor
    | ClearDecoArrowsEditor
    | AnimationTick Posix
    | WhiteSideColor Pieces.SideColor
    | BlackSideColor Pieces.SideColor
    | HttpError Http.Error


save : Model -> Shared.Model -> Shared.Model
save model shared =
    shared


load : Shared.Model -> Model -> ( Model, Cmd Msg )
load shared model =
    ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Browser.Events.onKeyUp (Decode.map KeyUp decodeKeyStroke)
        , Api.Ports.responseSvgNodeContent SvgReadyForDownload
        , Animation.subscription model.timeline AnimationTick
        ]


{-| Let the animation know about the current time.
-}
updateTimeline : Posix -> Model -> Model
updateTimeline now model =
    { model | timeline = Animation.tick now model.timeline }


decodeKeyStroke : Decoder KeyStroke
decodeKeyStroke =
    Decode.map3 KeyStroke
        (Decode.field "key" Decode.string)
        (Decode.field "ctrlKey" Decode.bool)
        (Decode.field "altKey" Decode.bool)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        EditorMsgNoOp ->
            ( model, Cmd.none )

        MouseDown mouse ->
            case model.inputMode of
                Nothing ->
                    let
                        dragData =
                            { start = mouse, current = mouse }
                    in
                    case mouse.tile of
                        Just tile ->
                            ( clickStart tile { model | drag = Just dragData }, Cmd.none )

                        Nothing ->
                            ( model, Cmd.none )

                Just mode ->
                    ( { model | castingDeco = CastingDeco.mouseDown mode mouse model.castingDeco }, Cmd.none )

        MouseMove mouse ->
            case model.inputMode of
                Nothing ->
                    ( handleMouseMove mouse model, Cmd.none )

                Just mode ->
                    ( { model | castingDeco = CastingDeco.mouseMove mode mouse model.castingDeco }, Cmd.none )

        MouseUp mouse ->
            case model.inputMode of
                Nothing ->
                    let
                        drag =
                            moveDrag mouse model.drag
                    in
                    case drag of
                        Nothing ->
                            ( { model | drag = Nothing }, Cmd.none )

                        Just dragData ->
                            ( clickRelease dragData.start dragData.current { model | drag = Nothing }, Cmd.none )

                Just mode ->
                    ( { model | castingDeco = CastingDeco.mouseUp mode mouse model.castingDeco }, Cmd.none )

        Undo ->
            ( applyUndo model, Cmd.none )

        Redo ->
            ( applyRedo model, Cmd.none )

        Reset newPosition ->
            ( { model
                | game = addHistoryState newPosition model.game
              }
                |> editorStateModify
                |> animateToCurrentPosition
            , Cmd.none
            )

        KeyUp stroke ->
            ( keyUp stroke model, Cmd.none )

        DownloadSvg ->
            ( model, Api.Ports.requestSvgNodeContent sakoEditorId )

        DownloadPng ->
            ( model
            , Api.Ports.triggerPngDownload
                (encodeDownloadRequest
                    { svgNode = sakoEditorId
                    , outputWidth = 1000
                    , outputHeight = 1000
                    }
                )
            )

        SvgReadyForDownload fileContent ->
            ( model, File.Download.string "pacoSako.svg" "image/svg+xml" fileContent )

        UpdateUserPaste pasteContent ->
            let
                parseInput () =
                    Sako.importExchangeNotation pasteContent
                        |> Result.mapError ParseError
                        |> Result.map ParseSuccess
                        |> Result.merge
            in
            ( { model
                | userPaste = pasteContent
                , pasteParsed =
                    if String.isEmpty pasteContent then
                        NoInput

                    else
                        parseInput ()
              }
            , Cmd.none
            )

        UseUserPaste newPosition ->
            ( { model
                | game = addHistoryState newPosition model.game
                , saveState = SaveDoesNotExist
              }
                |> animateToCurrentPosition
            , Cmd.none
            )

        SavePosition position saveState ->
            ( model
            , Api.Backend.postSave position saveState HttpError PositionSaveSuccess
            )

        PositionSaveSuccess data ->
            ( { model | saveState = saveStateStored data.id model.saveState }, Cmd.none )

        RequestRandomPosition ->
            ( model, Api.Backend.getRandomPosition HttpError GotRandomPosition )

        GotRandomPosition newPosition ->
            ( { model | game = addHistoryState newPosition model.game }
                |> animateToCurrentPosition
            , Cmd.none
            )

        RequestAnalysePosition position ->
            ( model, Api.Backend.postAnalysePosition position HttpError GotAnalysePosition )

        GotAnalysePosition analysis ->
            ( { model | analysis = Just analysis }, Cmd.none )

        ToolAddPiece color pieceType ->
            ( updateSmartToolAdd (P.getC model.game) color pieceType
                |> liftToolUpdate model
            , Cmd.none
            )

        SetExportOptionsVisible isVisible ->
            ( { model | showExportOptions = isVisible }, Cmd.none )

        SetInputModeEditor newMode ->
            ( { model | inputMode = newMode }, Cmd.none )

        ClearDecoTilesEditor ->
            ( { model | castingDeco = CastingDeco.clearTiles model.castingDeco }, Cmd.none )

        ClearDecoArrowsEditor ->
            ( { model | castingDeco = CastingDeco.clearArrows model.castingDeco }, Cmd.none )

        WhiteSideColor newSideColor ->
            ( { model | colorScheme = Pieces.setWhite newSideColor model.colorScheme }
            , Cmd.none
            )

        BlackSideColor newSideColor ->
            ( { model | colorScheme = Pieces.setBlack newSideColor model.colorScheme }
            , Cmd.none
            )

        AnimationTick now ->
            ( updateTimeline now model, Cmd.none )

        HttpError error ->
            ( model, Api.Ports.logToConsole (Api.Backend.describeError error) )


{-| Updates the save state and discards the analysis report.
-}
editorStateModify : Model -> Model
editorStateModify editorModel =
    { editorModel
        | saveState = saveStateModify editorModel.saveState
        , analysis = Nothing
    }


{-| Rolls back the editor state by one step.
-}
applyUndo : Model -> Model
applyUndo model =
    { model | game = P.withRollback P.goL model.game }
        |> animateToCurrentPosition


{-| Forwards the editor state by one step.
-}
applyRedo : Model -> Model
applyRedo model =
    { model | game = P.withRollback P.goR model.game }
        |> animateToCurrentPosition


{-| Handles all key presses.
-}
keyUp : KeyStroke -> Model -> Model
keyUp stroke model =
    if stroke.ctrlKey == False && stroke.altKey == False then
        regularKeyUp stroke.key model

    else if stroke.ctrlKey == True && stroke.altKey == False then
        ctrlKeyUp stroke.key model

    else
        model


{-| Handles all ctrl + <?> shortcuts.
-}
ctrlKeyUp : String -> Model -> Model
ctrlKeyUp key model =
    case key of
        "z" ->
            applyUndo model

        "y" ->
            applyRedo model

        _ ->
            model


regularKeyUp : String -> Model -> Model
regularKeyUp key model =
    case key of
        "Delete" ->
            deleteSelectedPiece model

        "Backspace" ->
            deleteSelectedPiece model

        _ ->
            model


deleteSelectedPiece : Model -> Model
deleteSelectedPiece model =
    let
        ( newTool, outMsg ) =
            updateSmartToolDelete (P.getC model.game) model.smartTool
    in
    handleToolOutputMsg outMsg
        { model | smartTool = newTool }


clickStart : Tile -> Model -> Model
clickStart downTile model =
    updateSmartToolStartDrag (P.getC model.game) downTile
        |> liftToolUpdate model


clickRelease : BoardMousePosition -> BoardMousePosition -> Model -> Model
clickRelease down up model =
    smartToolRelease down.tile up.tile model


smartToolRelease : Maybe Tile -> Maybe Tile -> Model -> Model
smartToolRelease down up model =
    case ( down, up ) of
        ( Just oldTileCoordinate, Just clickedTileCoordinate ) ->
            if oldTileCoordinate == clickedTileCoordinate then
                updateSmartToolClick (P.getC model.game) clickedTileCoordinate
                    |> liftToolUpdate model

            else
                updateSmartToolStopDrag (P.getC model.game) oldTileCoordinate clickedTileCoordinate
                    |> liftToolUpdate model

        _ ->
            liftToolUpdate model updateSmartToolDeselect


liftToolUpdate : Model -> (SmartToolModel -> ( SmartToolModel, ToolOutputMsg )) -> Model
liftToolUpdate model toolUpdate =
    let
        ( newTool, outMsg ) =
            toolUpdate model.smartTool
    in
    case outMsg of
        ToolNoOp ->
            { model | smartTool = newTool }

        ToolCommit position ->
            { model
                | game = addHistoryState position model.game
                , timeline =
                    model.timeline
                        |> Animation.interrupt (currentRenderData model)
                , preview = Nothing
                , smartTool = newTool
            }
                |> animateToCurrentPosition

        ToolPreview preview ->
            { model
                | preview = Just preview
                , smartTool = newTool
            }

        ToolRollback ->
            { model
                | preview = Nothing
                , smartTool = newTool
            }


animateToCurrentPosition : Model -> Model
animateToCurrentPosition editor =
    { editor
        | timeline =
            editor.timeline
                |> Animation.queue
                    ( animationSpeed
                    , currentRenderData editor
                    )
    }


{-| Determines how the editor should look right now. This also includes
interactivity that is currently running.
-}
currentRenderData : Model -> OpaqueRenderData
currentRenderData editor =
    editor.preview
        |> Maybe.withDefault (P.getC editor.game)
        |> PositionView.render (reduceSmartToolModel editor.smartTool)


handleToolOutputMsg : ToolOutputMsg -> Model -> Model
handleToolOutputMsg msg model =
    case msg of
        ToolNoOp ->
            model

        ToolCommit position ->
            { model
                | game = addHistoryState position model.game
                , timeline =
                    model.timeline
                        |> Animation.interrupt (currentRenderData model)
                , preview = Nothing
            }
                |> animateToCurrentPosition

        ToolPreview preview ->
            { model | preview = Just preview }

        ToolRollback ->
            { model | preview = Nothing }


animationSpeed : Animation.Duration
animationSpeed =
    Animation.milliseconds 250


handleMouseMove : BoardMousePosition -> Model -> Model
handleMouseMove mouse model =
    case model.drag of
        -- Moving the mouse when it is not held down.
        Nothing ->
            liftToolUpdate model
                (updateSmartToolHover (P.getC model.game) mouse.tile)

        --Moving the mouse when it is held down.
        Just { start } ->
            liftToolUpdate
                { model | drag = moveDrag mouse model.drag }
                (updateSmartToolContinueDrag start mouse)



--------------------------------------------------------------------------------
-- Editor > Smart Tool methods -------------------------------------------------
--------------------------------------------------------------------------------


moveDrag : BoardMousePosition -> DragState -> DragState
moveDrag current drag =
    Maybe.map
        (\dragData ->
            { start = dragData.start, current = current }
        )
        drag


pieceHighlighted : Tile -> Highlight -> Piece -> Bool
pieceHighlighted tile highlight piece =
    if Sako.isAt tile piece then
        case highlight of
            HighlightBoth ->
                True

            HighlightWhite ->
                Sako.isColor Sako.White piece

            HighlightBlack ->
                Sako.isColor Sako.Black piece

            HighlightLingering ->
                False

    else
        False


updateSmartToolClick : Sako.Position -> Tile -> SmartToolModel -> ( SmartToolModel, ToolOutputMsg )
updateSmartToolClick position tile model =
    case model.highlight of
        Just ( highlightTile, highlight ) ->
            if highlightTile == tile then
                if position.liftedPieces == [] then
                    updateSmartToolSelection position highlightTile model

                else
                    -- If a piece is lifted, we can't remove the highlight
                    ( smartToolRemoveDragInfo model, ToolRollback )

            else
                case doMoveAction highlightTile highlight tile position of
                    MoveIsIllegal ->
                        if position.liftedPieces == [] then
                            ( smartToolRemoveDragInfo
                                { model | highlight = Nothing }
                            , ToolRollback
                            )

                        else
                            -- If a piece is lifted, we can't remove the highlight
                            ( smartToolRemoveDragInfo model, ToolRollback )

                    SimpleMove newPosition ->
                        ( smartToolRemoveDragInfo
                            { model | highlight = Nothing }
                        , ToolCommit newPosition
                        )

                    MoveEndsWithLift newPosition newLiftedPiece ->
                        ( smartToolRemoveDragInfo
                            { model | highlight = Just ( newLiftedPiece.position, HighlightBoth ) }
                        , ToolCommit newPosition
                        )

        Nothing ->
            ( smartToolRemoveDragInfo
                { model | highlight = Just ( tile, HighlightBoth ) }
            , ToolRollback
            )


updateSmartToolHover : Sako.Position -> Maybe Tile -> SmartToolModel -> ( SmartToolModel, ToolOutputMsg )
updateSmartToolHover position maybeTile model =
    -- To show a hover marker, we need both a highlighted tile and a
    -- hovered tile. Otherwise we don't do anything at all.
    Maybe.map2
        (\( highlightTile, _ ) hover ->
            if highlightTile == hover then
                -- We don't show a hover marker if we are above the
                -- highlighted tile.
                ( { model | hover = Nothing }, ToolNoOp )

            else if List.all (\p -> p.position /= highlightTile) position.pieces then
                -- If the highlight position is empty, then we don't show
                -- a highlighted tile either.
                ( { model | hover = Nothing }, ToolNoOp )

            else
                ( { model | hover = Just hover }, ToolNoOp )
        )
        model.highlight
        maybeTile
        |> Maybe.withDefault ( { model | hover = Nothing }, ToolNoOp )


updateSmartToolDeselect : SmartToolModel -> ( SmartToolModel, ToolOutputMsg )
updateSmartToolDeselect model =
    ( smartToolRemoveDragInfo { model | highlight = Nothing }, ToolRollback )


updateSmartToolDelete : Sako.Position -> SmartToolModel -> ( SmartToolModel, ToolOutputMsg )
updateSmartToolDelete position model =
    case model.highlight of
        Just ( highlightTile, highlight ) ->
            -- Delete all pieces that are currently selected.
            let
                deletionHighlight =
                    if highlight == HighlightLingering then
                        HighlightBoth

                    else
                        highlight

                deleteAction piece =
                    not (pieceHighlighted highlightTile deletionHighlight piece)

                newPosition =
                    { position | pieces = List.filter deleteAction position.pieces }
            in
            ( smartToolRemoveDragInfo
                { model | highlight = Just ( highlightTile, HighlightBoth ) }
            , ToolCommit newPosition
            )

        Nothing ->
            ( smartToolRemoveDragInfo model, ToolRollback )


updateSmartToolAdd : Sako.Position -> Sako.Color -> Sako.Type -> SmartToolModel -> ( SmartToolModel, ToolOutputMsg )
updateSmartToolAdd position color pieceType model =
    case model.highlight of
        Just ( highlightTile, _ ) ->
            let
                deleteAction piece =
                    piece.color /= color || piece.position /= highlightTile

                newPosition =
                    { position
                        | pieces =
                            { color = color
                            , position = highlightTile
                            , pieceType = pieceType
                            , identity = "addTool" ++ String.fromInt model.identityCounter
                            }
                                :: List.filter deleteAction position.pieces
                    }
            in
            ( smartToolRemoveDragInfo
                { model
                    | highlight = Just ( highlightTile, HighlightLingering )
                    , identityCounter = model.identityCounter + 1
                }
            , ToolCommit newPosition
            )

        Nothing ->
            ( smartToolRemoveDragInfo model, ToolRollback )


updateSmartToolStartDrag : Sako.Position -> Tile -> SmartToolModel -> ( SmartToolModel, ToolOutputMsg )
updateSmartToolStartDrag position startTile model =
    let
        highlightType =
            case model.highlight of
                Just ( highlightTile, highlight ) ->
                    if highlightTile == startTile && highlight /= HighlightLingering then
                        highlight

                    else
                        HighlightBoth

                Nothing ->
                    HighlightBoth

        deleteAction piece =
            pieceHighlighted startTile highlightType piece

        newPosition =
            case position.liftedPieces of
                [] ->
                    { position
                        | pieces = List.filter (not << deleteAction) position.pieces
                    }

                _ ->
                    { position | liftedPieces = [] }

        draggingPieces =
            case position.liftedPieces of
                [] ->
                    DraggingPiecesNormal (List.filter deleteAction position.pieces)

                [ liftedPiece ] ->
                    DraggingPiecesLifted liftedPiece

                ls ->
                    DraggingPiecesNormal ls
    in
    ( { model | dragStartTile = Just startTile, draggingPieces = draggingPieces }
    , ToolPreview newPosition
    )


updateSmartToolContinueDrag : BoardMousePosition -> BoardMousePosition -> SmartToolModel -> ( SmartToolModel, ToolOutputMsg )
updateSmartToolContinueDrag aPos bPos model =
    ( { model | dragDelta = Just (Svg.Coord (bPos.x - aPos.x) (bPos.y - aPos.y)) }
    , ToolNoOp
    )


updateSmartToolStopDrag : Sako.Position -> Tile -> Tile -> SmartToolModel -> ( SmartToolModel, ToolOutputMsg )
updateSmartToolStopDrag position startTile targetTile model =
    let
        highlightType =
            case model.highlight of
                Just ( highlightTile, highlight ) ->
                    if highlightTile == startTile && highlight /= HighlightLingering then
                        highlight

                    else
                        HighlightBoth

                Nothing ->
                    HighlightBoth
    in
    case doMoveAction startTile highlightType targetTile position of
        MoveIsIllegal ->
            ( smartToolRemoveDragInfo
                { model | highlight = Nothing }
            , ToolRollback
            )

        SimpleMove newPosition ->
            ( smartToolRemoveDragInfo
                { model | highlight = Nothing }
            , ToolCommit newPosition
            )

        MoveEndsWithLift newPosition newLiftedPiece ->
            ( smartToolRemoveDragInfo
                { model | highlight = Just ( newLiftedPiece.position, HighlightBoth ) }
            , ToolCommit newPosition
            )


updateSmartToolSelection : Sako.Position -> Tile -> SmartToolModel -> ( SmartToolModel, ToolOutputMsg )
updateSmartToolSelection position highlightTile model =
    let
        pieceCountOnSelectedTile =
            position.pieces
                |> List.filter (Sako.isAt highlightTile)
                |> List.length
    in
    if pieceCountOnSelectedTile > 1 then
        -- If there are two pieces, cycle through selection states.
        ( smartToolRemoveDragInfo
            { model
                | highlight = nextHighlight highlightTile model.highlight
            }
        , ToolRollback
        )

    else
        -- If there is only one piece, then we remove the selection.
        ( smartToolRemoveDragInfo
            { model | highlight = Nothing }
        , ToolRollback
        )


{-| Indicates what happes in a move action and is used to inform the state of
the user interface.
-}
type MoveExecutionType
    = SimpleMove Sako.Position
    | MoveIsIllegal
    | MoveEndsWithLift Sako.Position Piece


{-| Tries to move the highlighted pieces at the source tile to the target tile,
following standard Paco Ŝako rules. If this is not possible, this method returns
Nothing instead of executing the move.

This function operates under the assumption, that sourceTile /= targetTile.

-}
doMoveAction : Tile -> Highlight -> Tile -> Sako.Position -> MoveExecutionType
doMoveAction sourceTile highlight targetTile position =
    if highlight == HighlightBoth then
        -- This is the easy branch, where we just do a normal move
        if List.isEmpty position.liftedPieces then
            Sako.doAction (Sako.Lift sourceTile) position
                |> Maybe.andThen (Sako.doAction (Sako.Place targetTile))
                |> Maybe.map convertToMoveExecution
                |> Maybe.withDefault MoveIsIllegal

        else
            Sako.doAction (Sako.Place targetTile) position
                |> Maybe.map convertToMoveExecution
                |> Maybe.withDefault MoveIsIllegal

    else if List.isEmpty position.liftedPieces then
        -- This branch is a bit special, we need to first lift only the selected
        -- piece, because the Sako module has no concept of partial selection.
        let
            sourcePieceSelector piece =
                pieceHighlighted sourceTile highlight piece
        in
        { position
            | pieces = List.filter (not << sourcePieceSelector) position.pieces
            , liftedPieces = List.filter sourcePieceSelector position.pieces
        }
            |> Sako.doAction (Sako.Place targetTile)
            |> Maybe.map convertToMoveExecution
            |> Maybe.withDefault MoveIsIllegal

    else
        MoveIsIllegal


convertToMoveExecution : Sako.Position -> MoveExecutionType
convertToMoveExecution position =
    case position.liftedPieces of
        [] ->
            SimpleMove position

        [ lifted ] ->
            MoveEndsWithLift position lifted

        _ ->
            MoveIsIllegal


{-| Adds a new state, storing the current state in the history. If there currently is a redo chain
it is discarded.
-}
addHistoryState : a -> Pivot a -> Pivot a
addHistoryState newState p =
    if P.getC p == newState then
        p

    else
        p |> P.setR [] |> P.appendGoR newState



--------------------------------------------------------------------------------
-- VIEW ------------------------------------------------------------------------
--------------------------------------------------------------------------------


view : Model -> Document Msg
view model =
    { title = "Design Puzzles - pacoplay.com"
    , body =
        [ editorUi model
        ]
    }


editorUi : Model -> Element Msg
editorUi model =
    Element.row
        [ width fill, height fill, Element.scrollbarY ]
        [ positionView model
        , sidebar model
        ]


positionView : Model -> Element Msg
positionView editor =
    Element.el
        [ width fill
        , height fill
        , Element.scrollbarY
        , centerX
        ]
        (positionViewInner editor)


positionViewInner : Model -> Element Msg
positionViewInner editor =
    let
        config =
            editorViewConfig editor
    in
    case editor.preview of
        Nothing ->
            editor.timeline
                |> PositionView.viewTimeline config

        Just position ->
            PositionView.render (reduceSmartToolModel editor.smartTool) position
                |> PositionView.viewStatic config


editorViewConfig : Model -> PositionView.ViewConfig Msg
editorViewConfig editor =
    { colorScheme = editor.colorScheme
    , nodeId = Just sakoEditorId
    , decoration = toolDecoration editor
    , dragPieceData = dragPieceData editor
    , mouseDown = Just MouseDown
    , mouseUp = Just MouseUp
    , mouseMove = Just MouseMove
    , additionalSvg = Nothing
    , replaceViewport = Nothing
    }



--------------------------------------------------------------------------------
-- Editor viev -----------------------------------------------------------------
--------------------------------------------------------------------------------


castingDecoMappers : { tile : Tile -> BoardDecoration, arrow : Arrow -> BoardDecoration }
castingDecoMappers =
    { tile = CastingHighlight
    , arrow = CastingArrow
    }


toolDecoration : Model -> List BoardDecoration
toolDecoration model =
    let
        selectionHighlight =
            model.smartTool.highlight |> Maybe.map HighlightTile

        hoverHighlight =
            model.smartTool.hover |> Maybe.map PlaceTarget

        dragPiece =
            model.smartTool.dragStartTile
                |> Maybe.map (\tile -> HighlightTile ( tile, HighlightBoth ))
    in
    ([ selectionHighlight
     , hoverHighlight
     , dragPiece
     ]
        |> List.filterMap identity
    )
        ++ CastingDeco.toDecoration castingDecoMappers model.castingDeco


dragPieceData : Model -> List DragPieceData
dragPieceData model =
    case model.smartTool.draggingPieces of
        DraggingPiecesNormal pieceList ->
            List.map
                (\piece ->
                    let
                        (Svg.Coord dx dy) =
                            model.smartTool.dragDelta
                                |> Maybe.withDefault (Svg.Coord 0 0)

                        (Svg.Coord x y) =
                            coordinateOfTile piece.position
                    in
                    { color = piece.color
                    , pieceType = piece.pieceType
                    , coord = Svg.Coord (x + dx) (y + dy)
                    , identity = piece.identity
                    }
                )
                pieceList

        DraggingPiecesLifted singlePiece ->
            let
                (Svg.Coord dx dy) =
                    model.smartTool.dragDelta
                        |> Maybe.withDefault (Svg.Coord 0 0)

                (Svg.Coord x y) =
                    coordinateOfTile singlePiece.position

                (Svg.Coord offset_x offset_y) =
                    --handCoordinateOffset singlePiece.color
                    Svg.Coord 0 0
            in
            [ { color = singlePiece.color
              , pieceType = singlePiece.pieceType
              , coord = Svg.Coord (x + dx + offset_x) (y + dy + offset_y)
              , identity = singlePiece.identity
              }
            ]



--------------------------------------------------------------------------------
-- Smart Tool ------------------------------------------------------------------
--------------------------------------------------------------------------------


type alias SmartToolModel =
    { highlight : Maybe ( Tile, Highlight )
    , dragStartTile : Maybe Tile
    , dragDelta : Maybe Svg.Coord
    , draggingPieces : DraggingPieces
    , hover : Maybe Tile
    , identityCounter : Int
    }


reduceSmartToolModel : SmartToolModel -> PositionView.InternalModel
reduceSmartToolModel smart =
    { highlight = smart.highlight
    , dragStartTile = smart.dragStartTile
    , dragDelta = smart.dragDelta
    , hover = smart.hover
    , draggingPieces = smart.draggingPieces
    }


smartToolRemoveDragInfo : SmartToolModel -> SmartToolModel
smartToolRemoveDragInfo tool =
    { tool
        | dragStartTile = Nothing
        , draggingPieces = DraggingPiecesNormal []
        , dragDelta = Nothing
    }


initSmartTool : SmartToolModel
initSmartTool =
    { highlight = Nothing
    , dragStartTile = Nothing
    , dragDelta = Nothing
    , draggingPieces = DraggingPiecesNormal []
    , hover = Nothing
    , identityCounter = 0
    }


type ToolOutputMsg
    = ToolNoOp -- Don't do anything.
    | ToolCommit Sako.Position -- Add state to history.
    | ToolPreview Sako.Position -- Don't add this to the history.
    | ToolRollback -- Remove an ephemeral state that was set by ToolPreview


sakoEditorId : String
sakoEditorId =
    "sako-editor"



--------------------------------------------------------------------------------
-- Editor > Sidebar view -------------------------------------------------------
--------------------------------------------------------------------------------


sidebar : Model -> Element Msg
sidebar model =
    let
        exportOptions =
            if model.showExportOptions then
                [ hideExportOptions
                , Input.button [] { onPress = Just DownloadSvg, label = Element.text "Download as Svg" }
                , Input.button [] { onPress = Just DownloadPng, label = Element.text "Download as Png" }
                , markdownCopyPaste model
                ]

            else
                [ showExportOptions ]
    in
    Element.column [ width (fill |> Element.maximum 400), height fill, spacing 10, padding 10, Element.alignRight ]
        ([ sidebarActionButtons model.game
         , Element.text "Add piece:"
         , addPieceButtons Sako.White "White:" model.smartTool
         , addPieceButtons Sako.Black "Black:" model.smartTool
         , colorSchemeConfig model
         , CastingDeco.configView castingDecoMessagesEditor model.inputMode model.castingDeco
         , analysisResult model
         ]
            ++ exportOptions
        )


castingDecoMessagesEditor : CastingDeco.Messages Msg
castingDecoMessagesEditor =
    { setInputMode = SetInputModeEditor
    , clearTiles = ClearDecoTilesEditor
    , clearArrows = ClearDecoArrowsEditor
    }


hideExportOptions : Element Msg
hideExportOptions =
    Input.button [] { onPress = Just (SetExportOptionsVisible False), label = Element.text "Hide Export Options" }


showExportOptions : Element Msg
showExportOptions =
    Input.button [] { onPress = Just (SetExportOptionsVisible True), label = Element.text "Show Export Options" }


sidebarActionButtons : Pivot Sako.Position -> Element Msg
sidebarActionButtons p =
    Element.row [ width fill ]
        [ undo p
        , redo p
        , resetStartingBoard p
        , resetClearBoard p
        , randomPosition
        , analysePosition (P.getC p)
        ]


flatButton : Maybe a -> Element a -> Element a
flatButton onPress content =
    Input.button [ padding 10 ]
        { onPress = onPress
        , label = content
        }


{-| The undo button.
-}
undo : Pivot a -> Element Msg
undo p =
    if P.hasL p then
        flatButton (Just Undo) (icon [] Solid.arrowLeft)

    else
        flatButton Nothing (icon [ Font.color (Element.rgb255 150 150 150) ] Solid.arrowLeft)


{-| The redo button.
-}
redo : Pivot a -> Element Msg
redo p =
    if P.hasR p then
        flatButton (Just Redo) (icon [] Solid.arrowRight)

    else
        flatButton Nothing (icon [ Font.color (Element.rgb255 150 150 150) ] Solid.arrowRight)


resetStartingBoard : Pivot Sako.Position -> Element Msg
resetStartingBoard p =
    if P.getC p /= Sako.initialPosition then
        flatButton (Just (Reset Sako.initialPosition)) (icon [] Solid.home)

    else
        flatButton Nothing (icon [ Font.color (Element.rgb255 150 150 150) ] Solid.home)


resetClearBoard : Pivot Sako.Position -> Element Msg
resetClearBoard p =
    if P.getC p /= Sako.emptyPosition then
        flatButton (Just (Reset Sako.emptyPosition)) (icon [] Solid.broom)

    else
        flatButton Nothing (icon [ Font.color (Element.rgb255 150 150 150) ] Solid.broom)


randomPosition : Element Msg
randomPosition =
    flatButton (Just RequestRandomPosition) (icon [] Solid.dice)


analysePosition : Sako.Position -> Element Msg
analysePosition position =
    flatButton (Just (RequestAnalysePosition position)) (icon [] Solid.calculator)


addPieceButtons : Sako.Color -> String -> SmartToolModel -> Element Msg
addPieceButtons color text tool =
    let
        hasHighlight =
            tool.highlight /= Nothing
    in
    Element.wrappedRow [ width fill ]
        [ Element.text text
        , singleAddPieceButton hasHighlight color Sako.Pawn Solid.chessPawn
        , singleAddPieceButton hasHighlight color Sako.Rook Solid.chessRook
        , singleAddPieceButton hasHighlight color Sako.Knight Solid.chessKnight
        , singleAddPieceButton hasHighlight color Sako.Bishop Solid.chessBishop
        , singleAddPieceButton hasHighlight color Sako.Queen Solid.chessQueen
        , singleAddPieceButton hasHighlight color Sako.King Solid.chessKing
        ]


singleAddPieceButton : Bool -> Sako.Color -> Sako.Type -> Icon -> Element Msg
singleAddPieceButton hasHighlight color pieceType buttonIcon =
    let
        onPress =
            if hasHighlight then
                Just (ToolAddPiece color pieceType)

            else
                Nothing
    in
    Input.button []
        { onPress = onPress
        , label = Element.row [ padding 7 ] [ icon [] buttonIcon ]
        }


backgroundFocus : Bool -> List (Element.Attribute msg)
backgroundFocus isFocused =
    if isFocused then
        [ Background.color (Element.rgb255 200 200 200) ]

    else
        []


colorPicker : (Pieces.SideColor -> msg) -> Pieces.SideColor -> Pieces.SideColor -> Element msg
colorPicker msg currentColor newColor =
    let
        iconChoice =
            if currentColor == newColor then
                Solid.yinYang

            else
                Regular.circle
    in
    Input.button [ width fill, padding 5, Background.color (Pieces.colorUi newColor.stroke) ]
        { onPress = Just (msg newColor)
        , label =
            icon
                [ centerX
                , Font.color (Pieces.colorUi newColor.fill)
                ]
                iconChoice
        }


colorSchemeConfig : Model -> Element Msg
colorSchemeConfig taco =
    Element.column [ width fill, spacing 5 ]
        [ Element.text "Piece colors"
        , colorSchemeConfigWhite taco
        , colorSchemeConfigBlack taco
        ]


colorSchemeConfigWhite : Model -> Element Msg
colorSchemeConfigWhite taco =
    Element.row [ width fill ]
        [ colorPicker WhiteSideColor taco.colorScheme.white Pieces.whitePieceColor
        , colorPicker WhiteSideColor taco.colorScheme.white Pieces.redPieceColor
        , colorPicker WhiteSideColor taco.colorScheme.white Pieces.orangePieceColor
        , colorPicker WhiteSideColor taco.colorScheme.white Pieces.yellowPieceColor
        , colorPicker WhiteSideColor taco.colorScheme.white Pieces.greenPieceColor
        , colorPicker WhiteSideColor taco.colorScheme.white Pieces.bluePieceColor
        , colorPicker WhiteSideColor taco.colorScheme.white Pieces.purplePieceColor
        , colorPicker WhiteSideColor taco.colorScheme.white Pieces.pinkPieceColor
        , colorPicker WhiteSideColor taco.colorScheme.white Pieces.blackPieceColor
        ]


colorSchemeConfigBlack : Model -> Element Msg
colorSchemeConfigBlack taco =
    Element.wrappedRow [ width fill ]
        [ colorPicker BlackSideColor taco.colorScheme.black Pieces.whitePieceColor
        , colorPicker BlackSideColor taco.colorScheme.black Pieces.redPieceColor
        , colorPicker BlackSideColor taco.colorScheme.black Pieces.orangePieceColor
        , colorPicker BlackSideColor taco.colorScheme.black Pieces.yellowPieceColor
        , colorPicker BlackSideColor taco.colorScheme.black Pieces.greenPieceColor
        , colorPicker BlackSideColor taco.colorScheme.black Pieces.bluePieceColor
        , colorPicker BlackSideColor taco.colorScheme.black Pieces.purplePieceColor
        , colorPicker BlackSideColor taco.colorScheme.black Pieces.pinkPieceColor
        , colorPicker BlackSideColor taco.colorScheme.black Pieces.blackPieceColor
        ]


icon : List (Element.Attribute msg) -> Icon -> Element msg
icon attributes iconType =
    Element.el attributes (Element.html (viewIcon iconType))


markdownCopyPaste : Model -> Element Msg
markdownCopyPaste model =
    Element.column [ spacing 5 ]
        [ Element.text "Text notation you can store"
        , Input.multiline [ Font.family [ Font.monospace ] ]
            { onChange = \_ -> EditorMsgNoOp
            , text = Sako.exportExchangeNotation (P.getC model.game)
            , placeholder = Nothing
            , label = Input.labelHidden "Copy this to a text document for later use."
            , spellcheck = False
            }
        , Element.text "Recover state from notation"
        , Input.multiline [ Font.family [ Font.monospace ] ]
            { onChange = UpdateUserPaste
            , text = model.userPaste
            , placeholder = Just (Input.placeholder [] (Element.text "Paste level notation."))
            , label = Input.labelHidden "Paste level notation as you see above."
            , spellcheck = False
            }
        , parsedMarkdownPaste model
        ]


parsedMarkdownPaste : Model -> Element Msg
parsedMarkdownPaste model =
    case model.pasteParsed of
        NoInput ->
            Element.none

        ParseError error ->
            Element.text error

        ParseSuccess pacoPosition ->
            Input.button []
                { onPress = Just (UseUserPaste pacoPosition)
                , label =
                    Element.row [ spacing 5 ]
                        [ PositionView.renderStatic pacoPosition
                            |> PositionView.viewStatic
                                { colorScheme = model.colorScheme
                                , nodeId = Nothing
                                , decoration = []
                                , dragPieceData = []
                                , mouseDown = Nothing
                                , mouseUp = Nothing
                                , mouseMove = Nothing
                                , additionalSvg = Nothing
                                , replaceViewport = Nothing
                                }
                        , Element.text "Load"
                        ]
                        |> Element.map (\_ -> EditorMsgNoOp)
                }


analysisResult : Model -> Element msg
analysisResult editorModel =
    case editorModel.analysis of
        Just analysis ->
            Element.paragraph []
                [ Element.text analysis.text_summary
                ]

        Nothing ->
            Element.none



--------------------------------------------------------------------------------
-- REST api - Mostly moved to Api.Backend exept for some alias definitions. ----
--------------------------------------------------------------------------------


type alias SavePositionDone =
    { id : Int
    }


type alias AnalysisReport =
    { text_summary : String

    -- TODO: search_result: SakoSearchResult,
    }
