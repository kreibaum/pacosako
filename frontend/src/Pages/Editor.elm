module Pages.Editor exposing (Model, Msg, page)

import Animation exposing (Timeline)
import Api.Backend exposing (Replay)
import Api.Ports
import Api.Wasm as Wasm exposing (RpcResponse, rpcCall)
import CastingDeco
import Colors
import Components exposing (btn, viewButton, withMsg, withSmallIcon)
import Custom.Element exposing (icon)
import Custom.Events exposing (BoardMousePosition, KeyBinding, fireMsg, forKey, withCtrl)
import Dict exposing (Dict)
import Effect exposing (Effect)
import Element exposing (Element, centerX, column, el, fill, height, padding, paddingXY, px, row, scrollbarY, shrink, spacing, width)
import Element.Background as Background
import Element.Font as Font
import Element.Input as Input
import Fen
import File.Download
import FontAwesome.Icon exposing (Icon)
import FontAwesome.Regular as Regular
import FontAwesome.Solid as Solid
import Gen.Route as Route
import Header
import Http
import Json.Encode as Encode
import Maybe.Extra as Maybe
import Page
import Pieces
import Pivot as P exposing (Pivot)
import PositionView exposing (BoardDecoration(..), DragPieceData, DragState, DraggingPieces(..), Highlight(..), OpaqueRenderData, nextHighlight)
import Reactive
import Request exposing (Request)
import Result.Extra as Result
import Sako exposing (Piece, Tile(..))
import SaveState exposing (SaveState(..), saveStateModify)
import Shared
import Svg.Custom as Svg exposing (BoardRotation(..), coordinateOfTile)
import Time exposing (Posix)
import Translations as T
import Url
import View exposing (View)


page : Shared.Model -> Request -> Page.With Model Msg
page shared request =
    Page.advanced
        { init = init shared request
        , update = update
        , view = view shared
        , subscriptions = subscriptions
        }



-- INIT


type alias Model =
    { query : QueryParameter
    , rawUrl : Url.Url
    , saveState : SaveState
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


{-| This type hold possible query parameter that the editor page can use.
-}
type QueryParameter
    = QueryEmpty
    | QueryError
    | QueryReplay { gameKey : String, actionCount : Int }
    | QueryFen { fen : Sako.Position }


decodeQueryParameter : Dict String String -> QueryParameter
decodeQueryParameter dict =
    decodeQueryEmpty dict
        |> Maybe.orElse (decodeQueryReplay dict)
        |> Maybe.orElse (decodeQueryFen dict)
        |> Maybe.withDefault QueryError


decodeQueryReplay : Dict String String -> Maybe QueryParameter
decodeQueryReplay dict =
    Maybe.map2 (\g a -> QueryReplay { gameKey = g, actionCount = a })
        (Dict.get "game" dict)
        (Dict.get "action" dict |> Maybe.andThen String.toInt)


decodeQueryFen : Dict String String -> Maybe QueryParameter
decodeQueryFen dict =
    Maybe.map
        (\fen ->
            Fen.parseFen fen
                |> Maybe.map (\pos -> QueryFen { fen = pos })
                |> Maybe.withDefault QueryError
        )
        (Dict.get "fen" dict)


decodeQueryEmpty : Dict String String -> Maybe QueryParameter
decodeQueryEmpty dict =
    if Dict.isEmpty dict then
        Just QueryEmpty

    else
        Nothing


init : Shared.Model -> Request -> ( Model, Effect Msg )
init shared { query, url } =
    initialEditor url shared (decodeQueryParameter query)
        |> loadInitialData


initialEditor : Url.Url -> Shared.Model -> QueryParameter -> Model
initialEditor rawUrl shared query =
    { query = query
    , rawUrl = rawUrl
    , saveState = SaveNotRequired
    , game = P.singleton Sako.initialPosition
    , preview = Nothing
    , timeline = Animation.init (PositionView.renderStatic WhiteBottom Sako.initialPosition)
    , drag = Nothing
    , windowSize = shared.windowSize
    , userPaste = ""
    , pasteParsed = NoInput
    , analysis = Nothing
    , smartTool = initSmartTool
    , showExportOptions = Basics.False
    , castingDeco = CastingDeco.initModel
    , inputMode = Nothing
    , colorScheme = Pieces.defaultColorScheme
    }


{-| Given the initial state of the model, this function may trigger side effects
and modify the model.

This is used to conditionally load data from the server.

-}
loadInitialData : Model -> ( Model, Effect Msg )
loadInitialData model =
    case model.query of
        QueryReplay { gameKey, actionCount } ->
            ( model
            , Api.Backend.getReplay gameKey ReplayLoadingError (ReplayLoaded actionCount)
                |> Effect.fromCmd
            )

        QueryFen { fen } ->
            ( setTimelineToSingleton fen model, Effect.none )

        _ ->
            ( model, Effect.none )



-- UPDATE


type Msg
    = EditorMsgNoOp
    | MouseDown BoardMousePosition
    | MouseMove BoardMousePosition
    | MouseUp BoardMousePosition
    | Undo
    | Redo
    | DeleteSelectedPiece
    | Reset Sako.Position
    | Copy String
    | DownloadSvg
    | DownloadPng
    | SvgReadyForDownload String
    | UpdateUserPaste String
    | UseUserPaste Sako.Position
    | RequestRandomPosition
    | RequestAnalysePosition Sako.Position
    | WasmResponse RpcResponse
    | ToolAddPiece Sako.Color Sako.Type
    | SetExportOptionsVisible Bool
    | SetInputMode (Maybe CastingDeco.InputMode)
    | ClearDecoTiles
    | ClearDecoArrows
    | ClearDecoComplete
    | AnimationTick Posix
    | WhiteSideColor Pieces.SideColor
    | BlackSideColor Pieces.SideColor
    | HttpError Http.Error
    | ReplayLoadingError Http.Error
    | ReplayLoaded Int Replay
    | ToShared Shared.Msg


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Custom.Events.onKeyUp keybindings
        , Api.Ports.responseSvgNodeContent SvgReadyForDownload
        , Animation.subscription model.timeline AnimationTick
        , Wasm.rpcRespone WasmResponse
        ]


{-| The central pace to register all page wide shortcuts.
-}
keybindings : List (KeyBinding Msg)
keybindings =
    [ forKey "z" |> withCtrl |> fireMsg Undo
    , forKey "y" |> withCtrl |> fireMsg Redo
    , forKey "Delete" |> fireMsg DeleteSelectedPiece
    , forKey "Backspace" |> fireMsg DeleteSelectedPiece
    , forKey "1" |> fireMsg (SetInputMode Nothing)
    , forKey "2" |> fireMsg (SetInputMode (Just CastingDeco.InputTiles))
    , forKey "3" |> fireMsg (SetInputMode (Just CastingDeco.InputArrows))
    , forKey " " |> fireMsg ClearDecoComplete
    , forKey "0" |> fireMsg ClearDecoComplete
    , forKey "x" |> fireMsg ClearDecoComplete
    , forKey "q" |> fireMsg ClearDecoComplete
    , forKey "ArrowRight" |> fireMsg Redo
    , forKey "ArrowLeft" |> fireMsg Undo
    ]


{-| Let the animation know about the current time.
-}
updateTimeline : Posix -> Model -> Model
updateTimeline now model =
    { model | timeline = Animation.tick now model.timeline }


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        EditorMsgNoOp ->
            ( model, Effect.none )

        MouseDown mouse ->
            case model.inputMode of
                Nothing ->
                    let
                        dragData =
                            { start = mouse, current = mouse }
                    in
                    case mouse.tile of
                        Just tile ->
                            ( clickStart tile { model | drag = Just dragData }, Effect.none )

                        Nothing ->
                            ( model, Effect.none )

                Just mode ->
                    ( { model | castingDeco = CastingDeco.mouseDown mode mouse model.castingDeco }, Effect.none )

        MouseMove mouse ->
            case model.inputMode of
                Nothing ->
                    ( handleMouseMove mouse model, Effect.none )

                Just mode ->
                    ( { model | castingDeco = CastingDeco.mouseMove mode mouse model.castingDeco }, Effect.none )

        MouseUp mouse ->
            case model.inputMode of
                Nothing ->
                    let
                        drag =
                            moveDrag mouse model.drag
                    in
                    case drag of
                        Nothing ->
                            ( { model | drag = Nothing }, Effect.none )

                        Just dragData ->
                            ( clickRelease dragData.start dragData.current { model | drag = Nothing }, Effect.none )

                Just mode ->
                    ( { model | castingDeco = CastingDeco.mouseUp mode mouse model.castingDeco }, Effect.none )

        Undo ->
            ( applyUndo model, Effect.none )

        Redo ->
            ( applyRedo model, Effect.none )

        Reset newPosition ->
            ( { model
                | game = addHistoryState newPosition model.game
              }
                |> editorStateModify
                |> animateToCurrentPosition
            , Effect.none
            )

        DeleteSelectedPiece ->
            ( deleteSelectedPiece model, Effect.none )

        Copy text ->
            ( model, Api.Ports.copy text |> Effect.fromCmd )

        DownloadSvg ->
            ( model, Api.Ports.requestSvgNodeContent sakoEditorId |> Effect.fromCmd )

        DownloadPng ->
            ( model
            , Api.Ports.triggerPngDownload
                (encodeDownloadRequest
                    { svgNode = sakoEditorId
                    , outputWidth = 1000
                    , outputHeight = 1000
                    }
                )
                |> Effect.fromCmd
            )

        SvgReadyForDownload fileContent ->
            ( model, File.Download.string "pacoSako.svg" "image/svg+xml" fileContent |> Effect.fromCmd )

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
            , Effect.none
            )

        UseUserPaste newPosition ->
            ( { model
                | game = addHistoryState newPosition model.game
                , saveState = SaveDoesNotExist
              }
                |> animateToCurrentPosition
            , Effect.none
            )

        RequestRandomPosition ->
            ( model, Wasm.RandomPosition 3000 |> rpcCall |> Effect.fromCmd )

        RequestAnalysePosition position ->
            ( model, Wasm.AnalyzePosition { board_fen = Fen.writeFen position, action_history = [] } |> rpcCall |> Effect.fromCmd )

        WasmResponse response ->
            case response of
                Wasm.RandomPositionResponse fen ->
                    let
                        newPosition =
                            Fen.parseFen fen
                                |> Maybe.withDefault Sako.initialPosition
                    in
                    ( { model
                        | game = addHistoryState newPosition model.game
                      }
                        |> animateToCurrentPosition
                    , Effect.none
                    )

                Wasm.AnalyzePositionResponse report ->
                    ( { model | analysis = Just report.analysis }, Effect.none )

                _ ->
                    ( model, Effect.none )

        ToolAddPiece color pieceType ->
            ( updateSmartToolAdd (P.getC model.game) color pieceType
                |> liftToolUpdate model
            , Effect.none
            )

        SetExportOptionsVisible isVisible ->
            ( { model | showExportOptions = isVisible }, Effect.none )

        SetInputMode newMode ->
            ( { model | inputMode = newMode }, Effect.none )

        ClearDecoTiles ->
            ( { model | castingDeco = CastingDeco.clearTiles model.castingDeco }, Effect.none )

        ClearDecoArrows ->
            ( { model | castingDeco = CastingDeco.clearArrows model.castingDeco }, Effect.none )

        ClearDecoComplete ->
            ( { model | castingDeco = model.castingDeco |> CastingDeco.clearArrows |> CastingDeco.clearTiles }, Effect.none )

        WhiteSideColor newSideColor ->
            ( { model | colorScheme = Pieces.setWhite newSideColor model.colorScheme }
            , Effect.none
            )

        BlackSideColor newSideColor ->
            ( { model | colorScheme = Pieces.setBlack newSideColor model.colorScheme }
            , Effect.none
            )

        AnimationTick now ->
            ( updateTimeline now model, Effect.none )

        HttpError error ->
            ( model, Api.Ports.logToConsole (Api.Backend.describeError error) |> Effect.fromCmd )

        ReplayLoadingError error ->
            ( { model | query = QueryError }, Api.Ports.logToConsole (Api.Backend.describeError error) |> Effect.fromCmd )

        ReplayLoaded actionCount replay ->
            replayLoaded actionCount replay model

        ToShared outMsg ->
            ( model, Effect.fromShared outMsg )


{-| When a replay is loaded, play it until the given action count and than show
the resulting board in the editor.
-}
replayLoaded : Int -> Replay -> Model -> ( Model, Effect Msg )
replayLoaded actionCount replay model =
    let
        actions =
            List.take actionCount replay.actions |> List.map (\( a, _ ) -> a)

        maybeBoard =
            Sako.doActionsList actions Sako.initialPosition
    in
    case maybeBoard of
        Just board ->
            ( setTimelineToSingleton board model, Effect.none )

        Nothing ->
            ( { model | query = QueryError }, Effect.none )


{-| Use this method when opening the page to replace the inital state with a
different state. This will remove all the history that is currently stored.
-}
setTimelineToSingleton : Sako.Position -> Model -> Model
setTimelineToSingleton position model =
    { model
        | game = P.singleton position
        , timeline =
            Animation.queue
                ( animationSpeed, PositionView.renderStatic WhiteBottom position )
                model.timeline
    }


{-| Updates the save state and discards the analysis report.
-}
editorStateModify : Model -> Model
editorStateModify model =
    { model
        | saveState = saveStateModify model.saveState
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
animateToCurrentPosition model =
    { model
        | timeline =
            model.timeline
                |> Animation.queue
                    ( animationSpeed
                    , currentRenderData model
                    )
    }


{-| Determines how the editor should look right now. This also includes
interactivity that is currently running.
-}
currentRenderData : Model -> OpaqueRenderData
currentRenderData model =
    model.preview
        |> Maybe.withDefault (P.getC model.game)
        |> PositionView.render (reduceSmartToolModel model.smartTool)


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


view : Shared.Model -> Model -> View Msg
view shared model =
    { title = T.editorPageTitle
    , element =
        Header.wrapWithHeaderV2 shared
            ToShared
            { isRouteHighlighted = \r -> r == Route.Editor
            , isWithBackground = True
            }
            (maybeEditorUi shared model)
    }


{-| Check if the query parameter are actually an a good state, otherwise show
error page.
-}
maybeEditorUi : Shared.Model -> Model -> Element Msg
maybeEditorUi shared model =
    case model.query of
        QueryError ->
            Element.link [ padding 10, Font.underline, Font.color (Element.rgb 0 0 1) ]
                { url = Route.toHref Route.Editor, label = Element.text T.editorPageNotFound }

        _ ->
            editorUi shared model


editorUi : Shared.Model -> Model -> Element Msg
editorUi shared model =
    case Reactive.classify shared.windowSize of
        Reactive.Phone ->
            editorUiPhone model

        Reactive.Tablet ->
            editorUiDesktop model

        Reactive.Desktop ->
            editorUiDesktop model


editorUiPhone : Model -> Element Msg
editorUiPhone model =
    el [ centerX, width fill, height fill, scrollbarY ]
        (column
            [ width fill, height fill, spacing 10 ]
            [ Element.paragraph [] [ sharingHeader model ]
            , positionViewInner model
            , column [ width fill, height fill, spacing 10, padding 10, Element.alignRight ]
                (sidebarContent model)
            ]
        )


editorUiDesktop : Model -> Element Msg
editorUiDesktop model =
    el [ centerX, height fill, width (Element.maximum 1120 fill) ]
        (Element.row
            [ width fill, height fill, paddingXY 10 0, spacing 10 ]
            [ column [ width fill, height fill ]
                [ positionView model
                ]
            , column [ width (px 250), height fill, spacing 10, padding 10, Element.alignRight ]
                (sidebarContent model)
            ]
        )


{-| This header holds a link to the current position (using fen) which allows
easy sharing. It also has a button that will open the "more" export options
dialog.
-}
sharingHeader : Model -> Element Msg
sharingHeader model =
    let
        urlString =
            fenUrl model
    in
    [ Element.text urlString
        |> el [ Element.clip, width fill ]
    , btn T.copy |> withSmallIcon Regular.clipboard |> withMsg (Copy urlString) |> viewButton
    ]
        |> row
            [ width (shrink |> Element.maximum 600)
            , centerX
            , Element.clip
            , spacing 10
            , padding 15
            ]
        |> el [ width fill ]


fenUrl : Model -> String
fenUrl model =
    let
        rawUrl =
            model.rawUrl
    in
    { rawUrl | query = Just ("fen=" ++ (P.getC model.game |> Fen.writeFen |> Fen.urlEncode)) }
        |> Url.toString


positionView : Model -> Element Msg
positionView model =
    Element.el
        [ width fill
        , height fill
        , Element.scrollbarY
        , centerX
        , Element.inFront (sharingHeader model)
        ]
        (positionViewInner model)


positionViewInner : Model -> Element Msg
positionViewInner model =
    let
        config =
            boardViewConfig model
    in
    case model.preview of
        Nothing ->
            model.timeline
                |> PositionView.viewTimeline config

        Just position ->
            PositionView.render (reduceSmartToolModel model.smartTool) position
                |> PositionView.viewStatic config


boardViewConfig : Model -> PositionView.ViewConfig Msg
boardViewConfig model =
    { colorScheme =
        Colors.configToOptions Colors.defaultBoardColors
            |> Colors.withPieceColorScheme model.colorScheme
    , nodeId = Just sakoEditorId
    , decoration = toolDecoration model
    , dragPieceData = dragPieceData model
    , mouseDown = Just MouseDown
    , mouseUp = Just MouseUp
    , mouseMove = Just MouseMove
    , additionalSvg = Nothing
    , replaceViewport =
        Just
            { x = -10
            , y = -80
            , width = 820
            , height = 960
            }
    }



--------------------------------------------------------------------------------
-- Editor viev -----------------------------------------------------------------
--------------------------------------------------------------------------------


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
        ++ CastingDeco.toDecoration PositionView.castingDecoMappers model.castingDeco


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
                            coordinateOfTile WhiteBottom piece.position
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
                    coordinateOfTile WhiteBottom singlePiece.position

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
    , rotation = WhiteBottom
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


sidebarContent : Model -> List (Element Msg)
sidebarContent model =
    let
        exportOptions =
            if model.showExportOptions then
                [ hideExportOptions
                , Input.button [] { onPress = Just DownloadSvg, label = Element.text T.editorDownloadAsSvg }
                , Input.button [] { onPress = Just DownloadPng, label = Element.text T.editorDownloadAsPng }
                , markdownCopyPaste model
                ]

            else
                [ showExportOptions ]
    in
    [ sidebarActionButtons model.game
    , Element.text T.editorAddPiece
    , addPieceButtons Sako.White T.editorWhiteShort model.smartTool
    , addPieceButtons Sako.Black T.editorBlackShort model.smartTool
    , colorSchemeConfig model
    , CastingDeco.configView castingDecoMessages model.inputMode model.castingDeco
    , analysisResult model
    ]
        ++ exportOptions


castingDecoMessages : CastingDeco.Messages Msg
castingDecoMessages =
    { setInputMode = SetInputMode
    , clearTiles = ClearDecoTiles
    , clearArrows = ClearDecoArrows
    }


hideExportOptions : Element Msg
hideExportOptions =
    Input.button [] { onPress = Just (SetExportOptionsVisible False), label = Element.text T.editorExportOptionsHide }


showExportOptions : Element Msg
showExportOptions =
    Input.button [] { onPress = Just (SetExportOptionsVisible True), label = Element.text T.editorExportOptionsShow }


sidebarActionButtons : Pivot Sako.Position -> Element Msg
sidebarActionButtons p =
    row [ width fill ]
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
        , label = row [ padding 7 ] [ icon [] buttonIcon ]
        }


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
    column [ width fill, spacing 5 ]
        [ Element.text T.editorPieceColors
        , colorSchemeConfigWhite taco
        , colorSchemeConfigBlack taco
        ]


colorSchemeConfigWhite : Model -> Element Msg
colorSchemeConfigWhite taco =
    row [ width fill, Font.size 10 ]
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
    Element.wrappedRow [ width fill, Font.size 10 ]
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


markdownCopyPaste : Model -> Element Msg
markdownCopyPaste model =
    column [ spacing 5 ]
        [ Element.text T.editorLegacyNotationRecover
        , Input.multiline [ Font.family [ Font.monospace ] ]
            { onChange = UpdateUserPaste
            , text = model.userPaste
            , placeholder = Just (Input.placeholder [] (Element.text T.editorLegacyNotationPaste))
            , label = Input.labelHidden T.editorLegacyNotationPaste
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
                    row [ spacing 5 ]
                        [ PositionView.renderStatic WhiteBottom pacoPosition
                            |> PositionView.viewStatic
                                { colorScheme =
                                    Colors.configToOptions Colors.defaultBoardColors
                                        |> Colors.withPieceColorScheme model.colorScheme
                                , nodeId = Nothing
                                , decoration = []
                                , dragPieceData = []
                                , mouseDown = Nothing
                                , mouseUp = Nothing
                                , mouseMove = Nothing
                                , additionalSvg = Nothing
                                , replaceViewport = Nothing
                                }
                        , Element.text T.editorLegacyNotationLoad
                        ]
                        |> Element.map (\_ -> EditorMsgNoOp)
                }


analysisResult : Model -> Element msg
analysisResult model =
    case model.analysis of
        Just analysis ->
            Element.paragraph []
                [ Element.text analysis.text_summary
                ]

        Nothing ->
            Element.none



--------------------------------------------------------------------------------
-- REST api - Mostly moved to Api.Backend exept for some alias definitions. ----
--------------------------------------------------------------------------------


type alias AnalysisReport =
    { text_summary : String

    -- TODO: search_result: SakoSearchResult,
    }
