module Main exposing (main)

{-| The Main module is the starting point of an Elm application. Everything
the app does starts from here.
-}

import Animation exposing (Timeline)
import Arrow exposing (Arrow)
import Browser
import Browser.Events
import Element exposing (Element, centerX, centerY, fill, height, padding, spacing, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import EventsCustom exposing (BoardMousePosition)
import File.Download
import FontAwesome.Icon exposing (Icon, viewIcon)
import FontAwesome.Regular as Regular
import FontAwesome.Solid as Solid
import FontAwesome.Styles
import Html exposing (Html)
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import List.Extra as List
import Pieces
import Pivot as P exposing (Pivot)
import Ports
import PositionView exposing (BoardDecoration(..), DragPieceData, DragState, DraggingPieces(..), Highlight(..), OpaqueRenderData, SvgCoord(..), ViewMode(..), coordinateOfTile, nextHighlight)
import Result.Extra as Result
import Sako exposing (Piece, Tile(..))
import Time exposing (Posix)
import Timer
import Websocket exposing (CurrentMatchState)


main : Program Decode.Value Model Msg
main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }


type alias Model =
    { taco : Taco
    , page : Page
    , play : PlayModel
    , matchSetup : MatchSetupModel
    , editor : EditorModel
    , login : LoginModel
    }


type Page
    = PlayPage
    | MatchSetupPage
    | EditorPage
    | LoginPage


type alias User =
    { id : Int
    , username : String
    }


type alias Taco =
    { colorScheme : Pieces.ColorScheme
    , login : Maybe User
    , now : Posix
    }


type alias LoginModel =
    { usernameRaw : String
    , passwordRaw : String
    }


{-| Represents the possible save states a persisted object can have.

TODO: Add "Currently Saving", with and without id, then update saveStateStored
and saveStateModify accordingly

-}
type SaveState
    = SaveIsCurrent Int
    | SaveIsModified Int
    | SaveDoesNotExist
    | SaveNotRequired


{-| Update a save state when something is changed in the editor
-}
saveStateModify : SaveState -> SaveState
saveStateModify old =
    case old of
        SaveIsCurrent id ->
            SaveIsModified id

        SaveNotRequired ->
            SaveDoesNotExist

        otherwise ->
            otherwise


saveStateStored : Int -> SaveState -> SaveState
saveStateStored newId _ =
    SaveIsCurrent newId


saveStateId : SaveState -> Maybe Int
saveStateId saveState =
    case saveState of
        SaveIsCurrent id ->
            Just id

        SaveIsModified id ->
            Just id

        SaveDoesNotExist ->
            Nothing

        SaveNotRequired ->
            Nothing


type alias EditorModel =
    { saveState : SaveState
    , game : Pivot Sako.Position
    , preview : Maybe Sako.Position
    , timeline : Timeline OpaqueRenderData
    , drag : DragState
    , windowSize : ( Int, Int )
    , userPaste : String
    , pasteParsed : PositionParseResult
    , viewMode : ViewMode
    , analysis : Maybe AnalysisReport
    , smartTool : SmartToolModel
    , shareStatus : Websocket.ShareStatus
    , rawShareKey : String
    , showExportOptions : Bool
    , castingDecoTileMarkers : List Tile
    , castingDecoArrows : List Arrow
    , ghostArrow : Maybe Arrow
    , inputMode : EditorInputMode
    }


type EditorInputMode
    = EditorInputNormal
    | EditorInputTiles
    | EditorInputArrows


type PositionParseResult
    = NoInput
    | ParseError String
    | ParseSuccess Sako.Position


type alias SmartToolModel =
    { highlight : Maybe ( Tile, Highlight )
    , dragStartTile : Maybe Tile
    , dragDelta : Maybe SvgCoord
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


type Msg
    = PlayMsgWrapper PlayMsg
    | MatchSetupMsgWrapper MatchSetupMsg
    | EditorMsgWrapper EditorMsg
    | LoginPageMsgWrapper LoginPageMsg
    | OpenPage Page
    | WhiteSideColor Pieces.SideColor
    | BlackSideColor Pieces.SideColor
    | HttpError Http.Error
    | LoginSuccess User
    | LogoutSuccess
    | AnimationTick Posix
    | WebsocketMsg Websocket.ServerMessage
    | WebsocketErrorMsg Decode.Error
    | UpdateNow Posix


{-| Messages that may only affect data in the position editor page.
-}
type EditorMsg
    = EditorMsgNoOp
    | MouseDown BoardMousePosition
    | MouseMove BoardMousePosition
    | MouseUp BoardMousePosition
    | WindowResize Int Int
    | Undo
    | Redo
    | Reset Sako.Position
    | KeyUp KeyStroke
    | DownloadSvg
    | DownloadPng
    | SvgReadyForDownload String
    | UpdateUserPaste String
    | UseUserPaste Sako.Position
    | SetViewMode ViewMode
    | SavePosition Sako.Position SaveState
    | PositionSaveSuccess SavePositionDone
    | RequestRandomPosition
    | GotRandomPosition Sako.Position
    | RequestAnalysePosition Sako.Position
    | GotAnalysePosition AnalysisReport
    | ToolAddPiece Sako.Color Sako.Type
    | StartSharing
    | GotSharingResult Websocket.ShareStatus
    | InputRawShareKey String
    | WebsocketConnect String
    | SetExportOptionsVisible Bool
    | SetInputMode EditorInputMode
    | ClearDecoTiles
    | ClearDecoArrows


type LoginPageMsg
    = TypeUsername String
    | TypePassword String
    | TryLogin
    | Logout


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


initialEditor : Decode.Value -> EditorModel
initialEditor flags =
    { saveState = SaveNotRequired
    , game = P.singleton Sako.initialPosition
    , preview = Nothing
    , timeline = Animation.init (PositionView.renderStatic Sako.initialPosition)
    , drag = Nothing
    , windowSize = parseWindowSize flags
    , userPaste = ""
    , pasteParsed = NoInput
    , viewMode = ShowNumbers
    , analysis = Nothing
    , smartTool = initSmartTool
    , shareStatus = Websocket.NotShared
    , rawShareKey = ""
    , showExportOptions = False
    , castingDecoTileMarkers = []
    , castingDecoArrows = []
    , ghostArrow = Nothing
    , inputMode = EditorInputNormal
    }


initialLogin : LoginModel
initialLogin =
    { usernameRaw = "", passwordRaw = "" }


initialTaco : Taco
initialTaco =
    { colorScheme = Pieces.defaultColorScheme, login = Nothing, now = Time.millisToPosix 0 }


parseWindowSize : Decode.Value -> ( Int, Int )
parseWindowSize value =
    Decode.decodeValue sizeDecoder value
        |> Result.withDefault ( 100, 100 )


sizeDecoder : Decoder ( Int, Int )
sizeDecoder =
    Decode.map2 (\x y -> ( x, y ))
        (Decode.field "width" Decode.int)
        (Decode.field "height" Decode.int)


init : Decode.Value -> ( Model, Cmd Msg )
init flags =
    ( { taco = initialTaco
      , page = MatchSetupPage
      , play = initPlayModel
      , matchSetup = initMatchSetupModel
      , editor = initialEditor flags
      , login = initialLogin
      }
    , getCurrentLogin
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        AnimationTick newTime ->
            ( updateTimeline newTime model, Cmd.none )

        PlayMsgWrapper playMsg ->
            let
                ( newPlay, cmd ) =
                    updatePlayModel playMsg model.play
            in
            ( { model | play = newPlay }, cmd )

        MatchSetupMsgWrapper matchSetupMsg ->
            let
                ( newMatchSetup, cmd ) =
                    updateMatchSetup matchSetupMsg model.matchSetup
            in
            ( { model | matchSetup = newMatchSetup }, cmd )

        EditorMsgWrapper editorMsg ->
            let
                ( editorModel, editorCmd ) =
                    updateEditor editorMsg model.editor
            in
            ( { model | editor = editorModel }, editorCmd )

        LoginPageMsgWrapper loginPageMsg ->
            let
                ( loginPageModel, loginPageCmd ) =
                    updateLoginPage loginPageMsg model.login
            in
            ( { model | login = loginPageModel }, loginPageCmd )

        WhiteSideColor newSideColor ->
            ( { model | taco = setColorScheme (Pieces.setWhite newSideColor model.taco.colorScheme) model.taco }
            , Cmd.none
            )

        BlackSideColor newSideColor ->
            ( { model | taco = setColorScheme (Pieces.setBlack newSideColor model.taco.colorScheme) model.taco }
            , Cmd.none
            )

        OpenPage newPage ->
            ( { model | page = newPage }
            , Cmd.none
            )

        LoginSuccess user ->
            ( { model
                | taco = setLoggedInUser user model.taco
                , login = initialLogin
              }
            , Cmd.none
            )

        LogoutSuccess ->
            ( { model
                | taco = removeLoggedInUser model.taco
                , login = initialLogin
              }
            , Cmd.none
            )

        HttpError error ->
            ( model, Ports.logToConsole (describeError error) )

        WebsocketMsg serverMessage ->
            updateWebsocket serverMessage model

        WebsocketErrorMsg error ->
            ( model, Ports.logToConsole (Decode.errorToString error) )

        UpdateNow posix ->
            let
                taco =
                    model.taco
            in
            ( { model | taco = { taco | now = posix } }, Cmd.none )


{-| Helper function to update the color scheme inside the taco.
-}
setColorScheme : Pieces.ColorScheme -> Taco -> Taco
setColorScheme colorScheme taco =
    { taco | colorScheme = colorScheme }


setLoggedInUser : User -> Taco -> Taco
setLoggedInUser user taco =
    { taco | login = Just user }


removeLoggedInUser : Taco -> Taco
removeLoggedInUser taco =
    { taco | login = Nothing }


updateEditor : EditorMsg -> EditorModel -> ( EditorModel, Cmd Msg )
updateEditor msg model =
    case msg of
        EditorMsgNoOp ->
            ( model, Cmd.none )

        MouseDown mouse ->
            case model.inputMode of
                EditorInputNormal ->
                    let
                        dragData =
                            { start = mouse, current = mouse }
                    in
                    case mouse.tile of
                        Just tile ->
                            clickStart tile { model | drag = Just dragData }

                        Nothing ->
                            ( model, Cmd.none )

                EditorInputArrows ->
                    ( { model | ghostArrow = Maybe.map2 Arrow mouse.tile mouse.tile }, Cmd.none )

                EditorInputTiles ->
                    ( model, Cmd.none )

        MouseMove mouse ->
            case model.inputMode of
                EditorInputNormal ->
                    handleMouseMove mouse model

                EditorInputArrows ->
                    case ( model.ghostArrow, mouse.tile ) of
                        ( Just arrow, Just head ) ->
                            ( { model | ghostArrow = Just { arrow | head = head } }, Cmd.none )

                        _ ->
                            ( model, Cmd.none )

                EditorInputTiles ->
                    ( model, Cmd.none )

        MouseUp mouse ->
            case model.inputMode of
                EditorInputNormal ->
                    let
                        drag =
                            moveDrag mouse model.drag
                    in
                    case drag of
                        Nothing ->
                            ( { model | drag = Nothing }, Cmd.none )

                        Just dragData ->
                            clickRelease dragData.start dragData.current { model | drag = Nothing }

                EditorInputTiles ->
                    switchCastingDecoTile mouse model

                EditorInputArrows ->
                    case ( model.ghostArrow, mouse.tile ) of
                        ( Just arrow, Just head ) ->
                            ( { model
                                | castingDecoArrows = flipEntry { arrow | head = head } model.castingDecoArrows
                                , ghostArrow = Nothing
                              }
                            , Cmd.none
                            )

                        _ ->
                            ( { model | ghostArrow = Nothing }, Cmd.none )

        WindowResize width height ->
            ( { model | windowSize = ( width, height ) }
            , Cmd.none
            )

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
            keyUp stroke model

        DownloadSvg ->
            ( model, Ports.requestSvgNodeContent sakoEditorId )

        DownloadPng ->
            ( model
            , Ports.triggerPngDownload
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

        SetViewMode newViewMode ->
            ( { model | viewMode = newViewMode }, Cmd.none )

        SavePosition position saveState ->
            ( model, postSave position saveState )

        PositionSaveSuccess data ->
            ( { model | saveState = saveStateStored data.id model.saveState }, Cmd.none )

        RequestRandomPosition ->
            ( model, getRandomPosition )

        GotRandomPosition newPosition ->
            ( { model | game = addHistoryState newPosition model.game }
                |> animateToCurrentPosition
            , Cmd.none
            )

        RequestAnalysePosition position ->
            ( model, postAnalysePosition position )

        GotAnalysePosition analysis ->
            ( { model | analysis = Just analysis }, Cmd.none )

        ToolAddPiece color pieceType ->
            updateSmartToolAdd (P.getC model.game) color pieceType
                |> liftToolUpdate model

        StartSharing ->
            ( { model | shareStatus = Websocket.ShareRequested }
            , postShareRequest model
            )

        GotSharingResult shareStatus ->
            ( { model | shareStatus = shareStatus }
            , case shareStatus of
                Websocket.ShareExists gameKey ->
                    Websocket.send (Websocket.Subscribe gameKey)

                _ ->
                    Cmd.none
            )

        InputRawShareKey rawShareKey ->
            ( { model | rawShareKey = rawShareKey }, Cmd.none )

        WebsocketConnect gameKey ->
            ( { model | shareStatus = Websocket.ShareRequested }
            , Websocket.send (Websocket.Subscribe gameKey)
            )

        SetExportOptionsVisible isVisible ->
            ( { model | showExportOptions = isVisible }, Cmd.none )

        SetInputMode newMode ->
            ( { model | inputMode = newMode }, Cmd.none )

        ClearDecoTiles ->
            ( { model | castingDecoTileMarkers = [] }, Cmd.none )

        ClearDecoArrows ->
            ( { model | castingDecoArrows = [] }, Cmd.none )


switchCastingDecoTile : BoardMousePosition -> EditorModel -> ( EditorModel, Cmd Msg )
switchCastingDecoTile mouse model =
    case mouse.tile of
        Just tile ->
            ( { model | castingDecoTileMarkers = flipEntry tile model.castingDecoTileMarkers }, Cmd.none )

        Nothing ->
            ( model, Cmd.none )


flipEntry : a -> List a -> List a
flipEntry entry list =
    if List.member entry list then
        List.remove entry list

    else
        entry :: list


editorStateModify : EditorModel -> EditorModel
editorStateModify editorModel =
    { editorModel
        | saveState = saveStateModify editorModel.saveState
        , analysis = Nothing
    }


applyUndo : EditorModel -> EditorModel
applyUndo model =
    { model | game = P.withRollback P.goL model.game }
        |> animateToCurrentPosition


applyRedo : EditorModel -> EditorModel
applyRedo model =
    { model | game = P.withRollback P.goR model.game }
        |> animateToCurrentPosition


{-| Handles all key presses.
-}
keyUp : KeyStroke -> EditorModel -> ( EditorModel, Cmd Msg )
keyUp stroke model =
    if stroke.ctrlKey == False && stroke.altKey == False then
        regularKeyUp stroke.key model

    else if stroke.ctrlKey == True && stroke.altKey == False then
        ctrlKeyUp stroke.key model

    else
        ( model, Cmd.none )


{-| Handles all ctrl + x shortcuts.
-}
ctrlKeyUp : String -> EditorModel -> ( EditorModel, Cmd Msg )
ctrlKeyUp key model =
    case key of
        "z" ->
            ( applyUndo model, Cmd.none )

        "y" ->
            ( applyRedo model, Cmd.none )

        _ ->
            ( model, Cmd.none )


regularKeyUp : String -> EditorModel -> ( EditorModel, Cmd Msg )
regularKeyUp key model =
    case key of
        "Delete" ->
            let
                ( newTool, outMsg ) =
                    updateSmartToolDelete (P.getC model.game) model.smartTool
            in
            handleToolOutputMsg outMsg
                { model | smartTool = newTool }

        _ ->
            ( model, Cmd.none )


clickStart : Tile -> EditorModel -> ( EditorModel, Cmd Msg )
clickStart downTile model =
    updateSmartToolStartDrag (P.getC model.game) downTile
        |> liftToolUpdate model


clickRelease : BoardMousePosition -> BoardMousePosition -> EditorModel -> ( EditorModel, Cmd Msg )
clickRelease down up model =
    smartToolRelease down.tile up.tile model


smartToolRelease : Maybe Tile -> Maybe Tile -> EditorModel -> ( EditorModel, Cmd Msg )
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


liftToolUpdate : EditorModel -> (SmartToolModel -> ( SmartToolModel, ToolOutputMsg )) -> ( EditorModel, Cmd Msg )
liftToolUpdate model toolUpdate =
    let
        ( newTool, outMsg ) =
            toolUpdate model.smartTool
    in
    case outMsg of
        ToolNoOp ->
            ( { model | smartTool = newTool }, Cmd.none )

        ToolCommit position ->
            ( { model
                | game = addHistoryState position model.game
                , timeline =
                    model.timeline
                        |> Animation.interrupt (currentRenderData model)
                , preview = Nothing
                , smartTool = newTool
              }
                |> animateToCurrentPosition
            , Websocket.send
                (Websocket.ClientNextStep
                    { index = P.lengthL model.game + 1
                    , step = Sako.encodePosition position
                    }
                )
            )

        ToolPreview preview ->
            ( { model
                | preview = Just preview
                , smartTool = newTool
              }
            , Cmd.none
            )

        ToolRollback ->
            ( { model
                | preview = Nothing
                , smartTool = newTool
              }
            , Cmd.none
            )


animateToCurrentPosition : EditorModel -> EditorModel
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
currentRenderData : EditorModel -> OpaqueRenderData
currentRenderData editor =
    editor.preview
        |> Maybe.withDefault (P.getC editor.game)
        |> PositionView.render (reduceSmartToolModel editor.smartTool)


handleToolOutputMsg : ToolOutputMsg -> EditorModel -> ( EditorModel, Cmd Msg )
handleToolOutputMsg msg model =
    case msg of
        ToolNoOp ->
            ( model, Cmd.none )

        ToolCommit position ->
            ( { model
                | game = addHistoryState position model.game
                , timeline =
                    model.timeline
                        |> Animation.interrupt (currentRenderData model)
                , preview = Nothing
              }
                |> animateToCurrentPosition
            , Websocket.send
                (Websocket.ClientNextStep
                    { index = P.lengthL model.game + 1
                    , step = Sako.encodePosition position
                    }
                )
            )

        ToolPreview preview ->
            ( { model | preview = Just preview }, Cmd.none )

        ToolRollback ->
            ( { model | preview = Nothing }, Cmd.none )


animationSpeed : Animation.Duration
animationSpeed =
    Animation.milliseconds 250


handleMouseMove : BoardMousePosition -> EditorModel -> ( EditorModel, Cmd Msg )
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
    ( { model | dragDelta = Just (SvgCoord (bPos.x - aPos.x) (bPos.y - aPos.y)) }
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
-- Handle websocket messages ---------------------------------------------------
--------------------------------------------------------------------------------


updateWebsocket : Websocket.ServerMessage -> Model -> ( Model, Cmd Msg )
updateWebsocket serverMessage model =
    case serverMessage of
        Websocket.TechnicalError errorMessage ->
            ( model, Ports.logToConsole errorMessage )

        Websocket.FullState syncronizedBoard ->
            let
                ( newEditor, cmd ) =
                    updateEditorWebsocketFullState syncronizedBoard model.editor
            in
            ( { model | editor = newEditor }, cmd )

        Websocket.ServerNextStep { index, step } ->
            let
                ( newEditor, cmd ) =
                    updateWebsocketNextStep index step model.editor
            in
            ( { model | editor = newEditor }, cmd )

        Websocket.NewMatchState data ->
            let
                ( newGame, cmd ) =
                    updatePlayCurrentMatchState data model.play
            in
            ( { model | play = newGame }, cmd )

        Websocket.MatchConnectionSuccess data ->
            let
                ( newGame, cmd ) =
                    updatePlayMatchConnectionSuccess data model.play
            in
            ( { model | play = newGame, page = PlayPage }, cmd )


updateEditorWebsocketFullState : { key : String, steps : List Value } -> EditorModel -> ( EditorModel, Cmd Msg )
updateEditorWebsocketFullState syncronizedBoard editor =
    case decodeSyncronizedSteps syncronizedBoard.steps of
        Ok (head :: tail) ->
            let
                game =
                    P.fromCons head tail
                        |> P.goToEnd
            in
            ( { editor
                | game = game
                , shareStatus = Websocket.ShareConnected syncronizedBoard.key
              }
                |> animateToCurrentPosition
            , Cmd.none
            )

        Ok [] ->
            ( editor, Ports.logToConsole "Server send a syncronized board without steps." )

        Err error ->
            ( editor, Ports.logToConsole (Decode.errorToString error) )


updateWebsocketNextStep : Int -> Value -> EditorModel -> ( EditorModel, Cmd Msg )
updateWebsocketNextStep index step editor =
    case P.goAbsolute (index - 1) editor.game of
        Just pivot ->
            case Decode.decodeValue Sako.decodePosition step of
                Ok newPacoPosition ->
                    ( { editor | game = addHistoryState newPacoPosition pivot }
                        |> animateToCurrentPosition
                    , Cmd.none
                    )

                Err decoderError ->
                    ( editor, Ports.logToConsole (Decode.errorToString decoderError) )

        Nothing ->
            -- We have experienced a desync error and need to reload the history.
            case Websocket.getGameKey editor.shareStatus of
                Just gameKey ->
                    ( { editor | shareStatus = Websocket.ShareExists gameKey }
                    , Websocket.send (Websocket.Subscribe gameKey)
                    )

                Nothing ->
                    ( editor
                    , Ports.logToConsole
                        "Server send a NextStep message while we were not subscribed to a board."
                    )


decodeSyncronizedSteps : List Value -> Result Decode.Error (List Sako.Position)
decodeSyncronizedSteps steps =
    steps
        |> List.map (Decode.decodeValue Sako.decodePosition)
        |> Result.combine


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Browser.Events.onResize WindowResize
            |> Sub.map EditorMsgWrapper
        , Browser.Events.onKeyUp (Decode.map KeyUp decodeKeyStroke)
            |> Sub.map EditorMsgWrapper
        , Ports.responseSvgNodeContent SvgReadyForDownload
            |> Sub.map EditorMsgWrapper
        , Websocket.listen WebsocketMsg WebsocketErrorMsg
        , Animation.subscription model.editor.timeline AnimationTick
        , Animation.subscription model.play.timeline (PlayMsgAnimationTick >> PlayMsgWrapper)
        , Time.every 1000 UpdateNow
        ]


decodeKeyStroke : Decoder KeyStroke
decodeKeyStroke =
    Decode.map3 KeyStroke
        (Decode.field "key" Decode.string)
        (Decode.field "ctrlKey" Decode.bool)
        (Decode.field "altKey" Decode.bool)


updateLoginPage : LoginPageMsg -> LoginModel -> ( LoginModel, Cmd Msg )
updateLoginPage msg loginPageModel =
    case msg of
        TypeUsername newText ->
            ( { loginPageModel | usernameRaw = newText }, Cmd.none )

        TypePassword newText ->
            ( { loginPageModel | passwordRaw = newText }, Cmd.none )

        TryLogin ->
            ( loginPageModel, postLoginPassword { username = loginPageModel.usernameRaw, password = loginPageModel.passwordRaw } )

        Logout ->
            ( loginPageModel, getLogout )


{-| Let the animation know about the current time.
-}
updateTimeline : Posix -> Model -> Model
updateTimeline now model =
    let
        oldEditorModel =
            model.editor

        newTimeline =
            Animation.tick now model.editor.timeline
    in
    { model | editor = { oldEditorModel | timeline = newTimeline } }



--------------------------------------------------------------------------------
-- View code -------------------------------------------------------------------
--------------------------------------------------------------------------------


view : Model -> Html Msg
view model =
    Element.layout [ height fill, Element.scrollbarY ] (globalUi model)


globalUi : Model -> Element Msg
globalUi model =
    case model.page of
        PlayPage ->
            playUi model.taco model.play

        MatchSetupPage ->
            matchSetupUi model.taco model.matchSetup

        EditorPage ->
            editorUi model.taco model.editor

        LoginPage ->
            loginUi model.taco model.login


type alias PageHeaderInfo =
    { currentPage : Page
    , targetPage : Page
    , caption : String
    }


{-| Header that is shared by all pages.
-}
pageHeader : Taco -> Page -> Element Msg -> Element Msg
pageHeader taco currentPage additionalHeader =
    Element.row [ width fill, Background.color (Element.rgb255 230 230 230) ]
        [ pageHeaderButton [] { currentPage = currentPage, targetPage = PlayPage, caption = "Play Paco Ŝako" }
        , pageHeaderButton [] { currentPage = currentPage, targetPage = EditorPage, caption = "Design Puzzles" }
        , additionalHeader
        , loginHeaderInfo taco
        ]


pageHeaderButton : List (Element.Attribute Msg) -> PageHeaderInfo -> Element Msg
pageHeaderButton attributes { currentPage, targetPage, caption } =
    Input.button
        (padding 10
            :: (backgroundFocus (currentPage == targetPage)
                    ++ attributes
               )
        )
        { onPress =
            if currentPage == targetPage then
                Nothing

            else
                Just (OpenPage targetPage)
        , label = Element.text caption
        }



--------------------------------------------------------------------------------
-- Editor viev -----------------------------------------------------------------
--------------------------------------------------------------------------------


editorUi : Taco -> EditorModel -> Element Msg
editorUi taco model =
    Element.column
        [ width fill
        , height fill
        , Element.scrollbarY
        ]
        [ Element.html FontAwesome.Styles.css
        , pageHeader taco EditorPage (saveStateHeader (P.getC model.game) model.saveState)
        , Element.row
            [ width fill, height fill, Element.scrollbarY ]
            [ positionView taco model |> Element.map EditorMsgWrapper
            , sidebar taco model
            ]
        ]


saveStateHeader : Sako.Position -> SaveState -> Element Msg
saveStateHeader position saveState =
    case saveState of
        SaveIsCurrent id ->
            Element.el [ padding 10, Font.color (Element.rgb255 150 200 150), Font.bold ] (Element.text <| "Saved. (id=" ++ String.fromInt id ++ ")")

        SaveIsModified id ->
            Input.button
                [ padding 10
                , Font.color (Element.rgb255 200 150 150)
                , Font.bold
                ]
                { onPress = Just (EditorMsgWrapper (SavePosition position saveState))
                , label = Element.text <| "Unsaved Changes! (id=" ++ String.fromInt id ++ ")"
                }

        SaveDoesNotExist ->
            Input.button
                [ padding 10
                , Font.color (Element.rgb255 200 150 150)
                , Font.bold
                ]
                { onPress = Just (EditorMsgWrapper (SavePosition position saveState))
                , label = Element.text "Unsaved Changes!"
                }

        SaveNotRequired ->
            Element.none


positionView : Taco -> EditorModel -> Element EditorMsg
positionView taco editor =
    Element.el
        [ width fill
        , height fill
        , Element.scrollbarY
        , centerX
        ]
        (positionViewInner taco editor)


positionViewInner : Taco -> EditorModel -> Element EditorMsg
positionViewInner taco editor =
    let
        config =
            editorViewConfig taco editor
    in
    case editor.preview of
        Nothing ->
            editor.timeline
                |> PositionView.viewTimeline config

        Just position ->
            PositionView.render (reduceSmartToolModel editor.smartTool) position
                |> PositionView.viewStatic config


editorViewConfig : Taco -> EditorModel -> PositionView.ViewConfig EditorMsg
editorViewConfig taco editor =
    { colorScheme = taco.colorScheme
    , viewMode = editor.viewMode
    , nodeId = Just sakoEditorId
    , decoration = toolDecoration editor
    , dragPieceData = dragPieceData editor
    , mouseDown = Just MouseDown
    , mouseUp = Just MouseUp
    , mouseMove = Just MouseMove
    }


toolDecoration : EditorModel -> List BoardDecoration
toolDecoration model =
    let
        selectionHighlight =
            model.smartTool.highlight |> Maybe.map HighlightTile

        hoverHighlight =
            model.smartTool.hover |> Maybe.map PlaceTarget

        dragPiece =
            model.smartTool.dragStartTile
                |> Maybe.map (\tile -> HighlightTile ( tile, HighlightBoth ))

        castingArrowsDeco =
            model.castingDecoArrows
                |> List.map CastingArrow

        castingGhostArrow =
            model.ghostArrow
                |> Maybe.map CastingArrow

        castingHighlightDeco =
            model.castingDecoTileMarkers
                |> List.map CastingHighlight
    in
    ([ selectionHighlight
     , hoverHighlight
     , dragPiece
     , castingGhostArrow
     ]
        |> List.filterMap identity
    )
        ++ castingArrowsDeco
        ++ castingHighlightDeco


dragPieceData : EditorModel -> List DragPieceData
dragPieceData model =
    case model.smartTool.draggingPieces of
        DraggingPiecesNormal pieceList ->
            List.map
                (\piece ->
                    let
                        (SvgCoord dx dy) =
                            model.smartTool.dragDelta
                                |> Maybe.withDefault (SvgCoord 0 0)

                        (SvgCoord x y) =
                            coordinateOfTile piece.position
                    in
                    { color = piece.color
                    , pieceType = piece.pieceType
                    , coord = SvgCoord (x + dx) (y + dy)
                    , identity = piece.identity
                    }
                )
                pieceList

        DraggingPiecesLifted singlePiece ->
            let
                (SvgCoord dx dy) =
                    model.smartTool.dragDelta
                        |> Maybe.withDefault (SvgCoord 0 0)

                (SvgCoord x y) =
                    coordinateOfTile singlePiece.position

                (SvgCoord offset_x offset_y) =
                    --handCoordinateOffset singlePiece.color
                    SvgCoord 0 0
            in
            [ { color = singlePiece.color
              , pieceType = singlePiece.pieceType
              , coord = SvgCoord (x + dx + offset_x) (y + dy + offset_y)
              , identity = singlePiece.identity
              }
            ]



--------------------------------------------------------------------------------
-- Editor > Sidebar view -------------------------------------------------------
--------------------------------------------------------------------------------


sidebar : Taco -> EditorModel -> Element Msg
sidebar taco model =
    let
        exportOptions =
            if model.showExportOptions then
                [ hideExportOptions
                , Input.button [] { onPress = Just (EditorMsgWrapper DownloadSvg), label = Element.text "Download as Svg" }
                , Input.button [] { onPress = Just (EditorMsgWrapper DownloadPng), label = Element.text "Download as Png" }
                , markdownCopyPaste taco model |> Element.map EditorMsgWrapper
                , analysisResult model
                ]

            else
                [ showExportOptions ]
    in
    Element.column [ width (fill |> Element.maximum 400), height fill, spacing 10, padding 10, Element.alignRight ]
        ([ sidebarActionButtons model.game |> Element.map EditorMsgWrapper
         , Element.text "Add piece:"
         , addPieceButtons Sako.White "White:" model.smartTool |> Element.map EditorMsgWrapper
         , addPieceButtons Sako.Black "Black:" model.smartTool |> Element.map EditorMsgWrapper
         , colorSchemeConfig taco
         , viewModeConfig model
         , shareButton model |> Element.map EditorMsgWrapper
         , shareInput model |> Element.map EditorMsgWrapper
         , tileInputMode model
         , arrowInputMode model
         ]
            ++ exportOptions
        )


hideExportOptions : Element Msg
hideExportOptions =
    Input.button [] { onPress = Just (EditorMsgWrapper (SetExportOptionsVisible False)), label = Element.text "Hide Export Options" }


showExportOptions : Element Msg
showExportOptions =
    Input.button [] { onPress = Just (EditorMsgWrapper (SetExportOptionsVisible True)), label = Element.text "Show Export Options" }


tileInputMode : EditorModel -> Element Msg
tileInputMode model =
    Element.row [ spacing 5 ]
        [ tileInputModeButton model
        , tileInputClearButton model
        ]


tileInputModeButton : EditorModel -> Element Msg
tileInputModeButton model =
    if model.inputMode == EditorInputTiles then
        Input.button
            [ Background.color (Element.rgb255 200 200 200), padding 3 ]
            { onPress = Just (EditorMsgWrapper (SetInputMode EditorInputNormal)), label = Element.text "Highlight On" }

    else
        Input.button [ padding 3 ]
            { onPress = Just (EditorMsgWrapper (SetInputMode EditorInputTiles)), label = Element.text "Highlight Off" }


tileInputClearButton : EditorModel -> Element Msg
tileInputClearButton model =
    if List.isEmpty model.castingDecoTileMarkers then
        Input.button
            [ Font.color (Element.rgb255 128 128 128) ]
            { onPress = Nothing, label = Element.text "Clear Highlight" }

    else
        Input.button []
            { onPress = Just (EditorMsgWrapper ClearDecoTiles), label = Element.text "Clear Highlight" }


arrowInputMode : EditorModel -> Element Msg
arrowInputMode model =
    Element.row [ spacing 5 ]
        [ arrowInputModeButton model
        , arrowInputClearButton model
        ]


arrowInputModeButton : EditorModel -> Element Msg
arrowInputModeButton model =
    if model.inputMode == EditorInputArrows then
        Input.button
            [ Background.color (Element.rgb255 200 200 200), padding 3 ]
            { onPress = Just (EditorMsgWrapper (SetInputMode EditorInputNormal)), label = Element.text "Arrows On" }

    else
        Input.button [ padding 3 ]
            { onPress = Just (EditorMsgWrapper (SetInputMode EditorInputArrows)), label = Element.text "Arrows Off" }


arrowInputClearButton : EditorModel -> Element Msg
arrowInputClearButton model =
    if List.isEmpty model.castingDecoArrows then
        Input.button
            [ Font.color (Element.rgb255 128 128 128) ]
            { onPress = Nothing, label = Element.text "Clear Arrows" }

    else
        Input.button []
            { onPress = Just (EditorMsgWrapper ClearDecoArrows), label = Element.text "Clear Arrows" }


sidebarActionButtons : Pivot Sako.Position -> Element EditorMsg
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
undo : Pivot a -> Element EditorMsg
undo p =
    if P.hasL p then
        flatButton (Just Undo) (icon [] Solid.arrowLeft)

    else
        flatButton Nothing (icon [ Font.color (Element.rgb255 150 150 150) ] Solid.arrowLeft)


{-| The redo button.
-}
redo : Pivot a -> Element EditorMsg
redo p =
    if P.hasR p then
        flatButton (Just Redo) (icon [] Solid.arrowRight)

    else
        flatButton Nothing (icon [ Font.color (Element.rgb255 150 150 150) ] Solid.arrowRight)


resetStartingBoard : Pivot Sako.Position -> Element EditorMsg
resetStartingBoard p =
    if P.getC p /= Sako.initialPosition then
        flatButton (Just (Reset Sako.initialPosition)) (icon [] Solid.home)

    else
        flatButton Nothing (icon [ Font.color (Element.rgb255 150 150 150) ] Solid.home)


resetClearBoard : Pivot Sako.Position -> Element EditorMsg
resetClearBoard p =
    if P.getC p /= Sako.emptyPosition then
        flatButton (Just (Reset Sako.emptyPosition)) (icon [] Solid.broom)

    else
        flatButton Nothing (icon [ Font.color (Element.rgb255 150 150 150) ] Solid.broom)


randomPosition : Element EditorMsg
randomPosition =
    flatButton (Just RequestRandomPosition) (icon [] Solid.dice)


analysePosition : Sako.Position -> Element EditorMsg
analysePosition position =
    flatButton (Just (RequestAnalysePosition position)) (icon [] Solid.calculator)


addPieceButtons : Sako.Color -> String -> SmartToolModel -> Element EditorMsg
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


singleAddPieceButton : Bool -> Sako.Color -> Sako.Type -> Icon -> Element EditorMsg
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


{-| A toolConfigOption represents one of several possible choices. If it represents the currently
choosen value (single selection only) it is highlighted. When clicked it will send a message.
-}
toolConfigOption : a -> (a -> msg) -> a -> String -> Element msg
toolConfigOption currentValue msg buttonValue caption =
    Input.button
        (padding 5
            :: backgroundFocus (currentValue == buttonValue)
        )
        { onPress = Just (msg buttonValue)
        , label =
            Element.text caption
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


colorSchemeConfig : Taco -> Element Msg
colorSchemeConfig taco =
    Element.column [ width fill, spacing 5 ]
        [ Element.text "Piece colors"
        , colorSchemeConfigWhite taco
        , colorSchemeConfigBlack taco
        ]


colorSchemeConfigWhite : Taco -> Element Msg
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


colorSchemeConfigBlack : Taco -> Element Msg
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


viewModeConfig : EditorModel -> Element Msg
viewModeConfig editor =
    Element.wrappedRow [ spacing 5 ]
        [ toolConfigOption editor.viewMode (SetViewMode >> EditorMsgWrapper) ShowNumbers "Show numbers"
        , toolConfigOption editor.viewMode (SetViewMode >> EditorMsgWrapper) CleanBoard "Hide numbers"
        ]


{-| The share button indicates what kind of board is currently shared and how
-}
shareButton : EditorModel -> Element EditorMsg
shareButton editor =
    case editor.shareStatus of
        Websocket.NotShared ->
            Input.button []
                { onPress = Just StartSharing
                , label =
                    Element.row [ spacing 5 ]
                        [ icon [] Solid.shareAlt, Element.text "Start sharing" ]
                }

        Websocket.ShareRequested ->
            Element.row [ spacing 5 ]
                [ icon [] Solid.hourglassHalf, Element.text "sharing ..." ]

        Websocket.ShareFailed _ ->
            Element.row [ spacing 5 ]
                [ icon [] Solid.exclamationTriangle, Element.text "Sharing error" ]

        Websocket.ShareExists gameKey ->
            Element.row [ spacing 5, Font.color (Element.rgb255 100 100 100) ]
                [ icon [] Solid.hourglassHalf, Element.text gameKey ]

        Websocket.ShareConnected gameKey ->
            Element.row [ spacing 5 ]
                [ icon [] Solid.plug, Element.text gameKey ]


postShareRequest : EditorModel -> Cmd Msg
postShareRequest editor =
    P.toList editor.game
        |> List.map Sako.encodePosition
        |> Websocket.share (GotSharingResult >> EditorMsgWrapper)


shareInput : EditorModel -> Element EditorMsg
shareInput editor =
    Element.row [ spacing 5 ]
        [ Input.text [ width (Element.px 100) ]
            { onChange = InputRawShareKey
            , text = editor.rawShareKey
            , placeholder = Nothing
            , label = Input.labelAbove [] (Element.text "Connect to a shared board.")
            }
        , Input.button []
            { onPress =
                Just (WebsocketConnect editor.rawShareKey)
            , label =
                Element.row [ spacing 5 ]
                    [ icon [] Solid.plug, Element.text "Connect" ]
            }
        ]


icon : List (Element.Attribute msg) -> Icon -> Element msg
icon attributes iconType =
    Element.el attributes (Element.html (viewIcon iconType))


markdownCopyPaste : Taco -> EditorModel -> Element EditorMsg
markdownCopyPaste taco model =
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
        , parsedMarkdownPaste taco model
        ]


parsedMarkdownPaste : Taco -> EditorModel -> Element EditorMsg
parsedMarkdownPaste taco model =
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
                                { colorScheme = taco.colorScheme
                                , viewMode = CleanBoard
                                , nodeId = Nothing
                                , decoration = []
                                , dragPieceData = []
                                , mouseDown = Nothing
                                , mouseUp = Nothing
                                , mouseMove = Nothing
                                }
                        , Element.text "Load"
                        ]
                        |> Element.map (\_ -> EditorMsgNoOp)
                }


analysisResult : EditorModel -> Element msg
analysisResult editorModel =
    case editorModel.analysis of
        Just analysis ->
            Element.paragraph []
                [ Element.text analysis.text_summary
                ]

        Nothing ->
            Element.none



--------------------------------------------------------------------------------
-- Login ui --------------------------------------------------------------------
--------------------------------------------------------------------------------


loginUi : Taco -> LoginModel -> Element Msg
loginUi taco loginPageData =
    Element.column [ width fill ]
        [ Element.html FontAwesome.Styles.css
        , pageHeader taco LoginPage Element.none
        , case taco.login of
            Just user ->
                loginInfoPage user

            Nothing ->
                loginDialog taco loginPageData
        ]


loginDialog : Taco -> LoginModel -> Element Msg
loginDialog _ loginPageData =
    Element.column []
        [ Input.username []
            { label = Input.labelAbove [] (Element.text "Username")
            , onChange = TypeUsername >> LoginPageMsgWrapper
            , placeholder = Just (Input.placeholder [] (Element.text "Username"))
            , text = loginPageData.usernameRaw
            }
        , Input.currentPassword []
            { label = Input.labelAbove [] (Element.text "Password")
            , onChange = TypePassword >> LoginPageMsgWrapper
            , placeholder = Just (Input.placeholder [] (Element.text "Password"))
            , text = loginPageData.passwordRaw
            , show = False
            }
        , Input.button [] { label = Element.text "Login", onPress = Just (LoginPageMsgWrapper TryLogin) }
        ]


loginInfoPage : User -> Element Msg
loginInfoPage user =
    Element.column [ padding 10, spacing 10 ]
        [ Element.text ("Username: " ++ user.username)
        , Element.text ("ID: " ++ String.fromInt user.id)
        , Input.button [] { label = Element.text "Logout", onPress = Just (LoginPageMsgWrapper Logout) }
        ]


loginHeaderInfo : Taco -> Element Msg
loginHeaderInfo taco =
    let
        loginCaption =
            case taco.login of
                Just user ->
                    Element.row [ padding 10, spacing 10 ] [ icon [] Solid.user, Element.text user.username ]

                Nothing ->
                    Element.row [ padding 10, spacing 10 ] [ icon [] Solid.signInAlt, Element.text "Login" ]
    in
    Input.button [ Element.alignRight ]
        { onPress = Just (OpenPage LoginPage), label = loginCaption }



--------------------------------------------------------------------------------
-- REST api --------------------------------------------------------------------
--------------------------------------------------------------------------------


describeError : Http.Error -> String
describeError error =
    case error of
        Http.BadUrl url ->
            "Bad url: " ++ url

        Http.Timeout ->
            "Timeout error."

        Http.NetworkError ->
            "Network error."

        Http.BadStatus statusCode ->
            "Bad status: " ++ String.fromInt statusCode

        Http.BadBody body ->
            "Bad body: " ++ body


defaultErrorHandler : (a -> Msg) -> Result Http.Error a -> Msg
defaultErrorHandler happyPath result =
    case result of
        Ok username ->
            happyPath username

        Err error ->
            HttpError error


type alias LoginData =
    { username : String
    , password : String
    }


encodeLoginData : LoginData -> Value
encodeLoginData record =
    Encode.object
        [ ( "username", Encode.string <| record.username )
        , ( "password", Encode.string <| record.password )
        ]


decodeUser : Decoder User
decodeUser =
    Decode.map2 User
        (Decode.field "user_id" Decode.int)
        (Decode.field "username" Decode.string)


postLoginPassword : LoginData -> Cmd Msg
postLoginPassword data =
    Http.post
        { url = "/api/login/password"
        , body = Http.jsonBody (encodeLoginData data)
        , expect = Http.expectJson (defaultErrorHandler LoginSuccess) decodeUser
        }


getCurrentLogin : Cmd Msg
getCurrentLogin =
    Http.get
        { url = "/api/user_id"
        , expect =
            Http.expectJson
                (\result ->
                    case result of
                        Ok payload ->
                            LoginSuccess payload

                        Err err ->
                            HttpError err
                )
                decodeUser
        }


getLogout : Cmd Msg
getLogout =
    Http.get
        { url = "/api/logout"
        , expect = Http.expectWhatever (defaultErrorHandler (\() -> LogoutSuccess))
        }


postSave : Sako.Position -> SaveState -> Cmd Msg
postSave position saveState =
    case saveStateId saveState of
        Just id ->
            postSaveUpdate position id

        Nothing ->
            postSaveCreate position


{-| The server treats this object as an opaque JSON object.
-}
type alias CreatePositionData =
    { notation : String
    }


encodeCreatePositionData : CreatePositionData -> Value
encodeCreatePositionData record =
    Encode.object
        [ ( "notation", Encode.string <| record.notation )
        ]


encodeCreatePosition : Sako.Position -> Value
encodeCreatePosition position =
    Encode.object
        [ ( "data"
          , encodeCreatePositionData
                { notation = Sako.exportExchangeNotation position
                }
          )
        ]


type alias SavePositionDone =
    { id : Int
    }


decodeSavePositionDone : Decoder SavePositionDone
decodeSavePositionDone =
    Decode.map SavePositionDone
        (Decode.field "id" Decode.int)


postSaveCreate : Sako.Position -> Cmd Msg
postSaveCreate position =
    Http.post
        { url = "/api/position"
        , body = Http.jsonBody (encodeCreatePosition position)
        , expect =
            Http.expectJson
                (defaultErrorHandler (EditorMsgWrapper << PositionSaveSuccess))
                decodeSavePositionDone
        }


postSaveUpdate : Sako.Position -> Int -> Cmd Msg
postSaveUpdate position id =
    Http.post
        { url = "/api/position/" ++ String.fromInt id
        , body = Http.jsonBody (encodeCreatePosition position)
        , expect =
            Http.expectJson
                (defaultErrorHandler (EditorMsgWrapper << PositionSaveSuccess))
                decodeSavePositionDone
        }


type alias StoredPositionData =
    { notation : String
    }


decodeStoredPositionData : Decoder StoredPositionData
decodeStoredPositionData =
    Decode.map StoredPositionData
        (Decode.field "notation" Decode.string)


decodePacoPositionData : Decoder Sako.Position
decodePacoPositionData =
    Decode.andThen
        (\json ->
            json.notation
                |> Sako.importExchangeNotation
                |> Result.map Decode.succeed
                |> Result.withDefault (Decode.fail "Data has wrong shape.")
        )
        decodeStoredPositionData


getRandomPosition : Cmd Msg
getRandomPosition =
    Http.get
        { url = "/api/random"
        , expect = Http.expectJson (defaultErrorHandler (EditorMsgWrapper << GotRandomPosition)) decodePacoPositionData
        }


type alias AnalysisReport =
    { text_summary : String

    -- TODO: search_result: SakoSearchResult,
    }


decodeAnalysisReport : Decoder AnalysisReport
decodeAnalysisReport =
    Decode.map AnalysisReport
        (Decode.field "text_summary" Decode.string)


postAnalysePosition : Sako.Position -> Cmd Msg
postAnalysePosition position =
    Http.post
        { url = "/api/analyse"
        , body = Http.jsonBody (encodeCreatePosition position)
        , expect =
            Http.expectJson
                (defaultErrorHandler (EditorMsgWrapper << GotAnalysePosition))
                decodeAnalysisReport
        }



--------------------------------------------------------------------------------
-- Playing Paco Ŝako -----------------------------------------------------------
--------------------------------------------------------------------------------
-- Set up a game and play it by the rules.
-- The rules are not known by the elm frontend and we need to query them from
-- the server.
-- I'll call this the "Play" page.


addActionToCurrentMatchState : Sako.Action -> CurrentMatchState -> CurrentMatchState
addActionToCurrentMatchState action state =
    { state
        | actionHistory = state.actionHistory ++ [ action ]
        , legalActions = []
    }


type alias PlayModel =
    { board : Sako.Position
    , subscription : Maybe String
    , currentState : CurrentMatchState

    -- later: , preview : Maybe Sako.Position
    , timeline : Timeline OpaqueRenderData
    , focus : Maybe Tile
    }


initPlayModel : PlayModel
initPlayModel =
    { board = Sako.initialPosition
    , subscription = Nothing
    , currentState =
        { key = ""
        , actionHistory = []
        , legalActions = []
        , controllingPlayer = Sako.White
        , timer = Nothing
        , gameState = Sako.Running
        }
    , timeline = Animation.init (PositionView.renderStatic Sako.initialPosition)
    , focus = Nothing
    }


type PlayMsg
    = PlayActionInputStep Sako.Action
    | PlayRollback
    | PlayMsgAnimationTick Posix
    | PlayMouseDown BoardMousePosition
    | PlayMouseUp BoardMousePosition
    | PlayMouseMove BoardMousePosition


updatePlayModel : PlayMsg -> PlayModel -> ( PlayModel, Cmd Msg )
updatePlayModel msg model =
    case msg of
        PlayActionInputStep action ->
            updateActionInputStep action model

        PlayMsgAnimationTick now ->
            ( { model | timeline = Animation.tick now model.timeline }, Cmd.none )

        PlayRollback ->
            ( model
            , Websocket.send (Websocket.Rollback (Maybe.withDefault "" model.subscription))
            )

        PlayMouseDown _ ->
            ( model, Cmd.none )

        PlayMouseUp pos ->
            -- Check if the position is an allowed action.
            case Maybe.andThen (legalActionAt model.currentState) pos.tile of
                Just action ->
                    updateActionInputStep action model

                Nothing ->
                    ( model, Cmd.none )

        PlayMouseMove _ ->
            ( model, Cmd.none )


legalActionAt : CurrentMatchState -> Tile -> Maybe Sako.Action
legalActionAt state tile =
    state.legalActions
        |> List.filter (\action -> Sako.actionTile action == Just tile)
        -- There can never be two actions on the same square, so this is safe.
        |> List.head


updateActionInputStep : Sako.Action -> PlayModel -> ( PlayModel, Cmd Msg )
updateActionInputStep action model =
    let
        newBoard =
            Sako.doAction action model.board
                |> Maybe.withDefault model.board
    in
    ( { model
        | board = newBoard
        , currentState = addActionToCurrentMatchState action model.currentState
        , timeline =
            Animation.queue
                ( Animation.milliseconds 200, PositionView.renderStatic newBoard )
                model.timeline
      }
    , Websocket.DoAction
        { key = Maybe.withDefault "" model.subscription
        , action = action
        }
        |> Websocket.send
    )


updatePlayCurrentMatchState : CurrentMatchState -> PlayModel -> ( PlayModel, Cmd Msg )
updatePlayCurrentMatchState data model =
    let
        newBoard =
            case matchStatesDiff model.currentState data of
                Just diffActions ->
                    doActions diffActions model.board
                        |> Maybe.withDefault model.board

                Nothing ->
                    doActions data.actionHistory Sako.initialPosition
                        |> Maybe.withDefault Sako.emptyPosition

        newState =
            data
    in
    ( { model
        | currentState = newState
        , board = newBoard
        , timeline =
            Animation.queue
                ( Animation.milliseconds 200, PositionView.renderStatic newBoard )
                model.timeline
      }
    , Cmd.none
    )


updatePlayMatchConnectionSuccess : { key : String, state : CurrentMatchState } -> PlayModel -> ( PlayModel, Cmd Msg )
updatePlayMatchConnectionSuccess data model =
    { model | subscription = Just data.key }
        |> updatePlayCurrentMatchState data.state


{-| Iterate doAction with the actions provided on the board state.
-}
doActions : List Sako.Action -> Sako.Position -> Maybe Sako.Position
doActions actions board =
    case actions of
        [] ->
            Just board

        a :: actionTail ->
            case Sako.doAction a board of
                Just b ->
                    doActions actionTail b

                Nothing ->
                    Nothing


{-| Given an old and a new match state, this returns the actions that need to
be taken to transform the old state into the new state. Returns Nothing if the
new state does not extend the old state.
-}
matchStatesDiff : CurrentMatchState -> CurrentMatchState -> Maybe (List Sako.Action)
matchStatesDiff old new =
    historyDiff old.actionHistory new.actionHistory


historyDiff : List a -> List a -> Maybe (List a)
historyDiff old new =
    case ( old, new ) of
        ( [], newTail ) ->
            Just newTail

        ( _, [] ) ->
            Nothing

        ( o :: oldTail, n :: newTail ) ->
            if o == n then
                historyDiff oldTail newTail

            else
                Nothing


playUi : Taco -> PlayModel -> Element Msg
playUi taco model =
    Element.column [ width fill, height fill, Element.scrollbarY ]
        [ Element.html FontAwesome.Styles.css
        , pageHeader taco PlayPage Element.none
        , Element.row
            [ width fill, height fill, Element.scrollbarY ]
            [ playPositionView taco model
            , playModeSidebar taco model
            ]
        ]


playPositionView : Taco -> PlayModel -> Element Msg
playPositionView taco play =
    Element.el [ width fill, height fill, Element.scrollbarY ]
        (PositionView.viewTimeline
            { colorScheme = taco.colorScheme
            , viewMode = ShowNumbers
            , nodeId = Just sakoEditorId
            , decoration = playDecoration play
            , dragPieceData = []
            , mouseDown = Just (PlayMouseDown >> PlayMsgWrapper)
            , mouseUp = Just (PlayMouseUp >> PlayMsgWrapper)
            , mouseMove = Just (PlayMouseMove >> PlayMsgWrapper)
            }
            play.timeline
        )


playDecoration : PlayModel -> List PositionView.BoardDecoration
playDecoration play =
    play.currentState.legalActions
        |> List.filterMap actionDecoration


actionDecoration : Sako.Action -> Maybe PositionView.BoardDecoration
actionDecoration action =
    case action of
        Sako.Place tile ->
            Just (PositionView.PlaceTarget tile)

        _ ->
            Nothing


playModeSidebar : Taco -> PlayModel -> Element Msg
playModeSidebar taco model =
    Element.column [ spacing 5, padding 20, height fill ]
        [ Element.el [ Element.alignTop, width fill ]
            (maybeViewTimerFor taco model Sako.Black)
        , model.subscription
            |> Maybe.map (\id -> Element.text ("Share this id with a friend: " ++ id))
            |> Maybe.withDefault (Element.text "Not connected")
        , bigRoundedButton (Element.rgb255 220 220 220)
            (Just (PlayRollback |> PlayMsgWrapper))
            [ Element.text "Restart Move" ]
            |> Element.el [ width fill ]
        , maybePromotionButtons model.currentState.legalActions
        , maybeVictoryStateInfo model.currentState.gameState
        , Element.el [ Element.alignBottom, width fill ]
            (maybeViewTimerFor taco model Sako.White)
        , Element.el [ height (Element.px 100) ] Element.none
        ]


maybeViewTimerFor : Taco -> PlayModel -> Sako.Color -> Element msg
maybeViewTimerFor taco model player =
    case model.currentState.timer of
        Just timer ->
            viewTimerFor taco.now model timer player

        Nothing ->
            bigRoundedTimerLabel (Element.rgb255 170 170 170)
                [ Element.text "No Timer" ]


viewTimerFor : Posix -> PlayModel -> Timer.Timer -> Sako.Color -> Element msg
viewTimerFor now model timer player =
    let
        viewData =
            Timer.render model.currentState.controllingPlayer now timer

        secondsLeft =
            if player == Sako.White then
                viewData.secondsLeftWhite

            else
                viewData.secondsLeftBlack

        color =
            if Just player == viewData.runningFor then
                Element.rgb255 200 240 200

            else
                Element.rgb255 170 170 170
    in
    bigRoundedTimerLabel color
        [ Element.text (timeLabel secondsLeft)
        ]


{-| A label that is implemented via a horizontal row with a big colored background.
Currently only used for the timer, not sure if it will stay that way.
-}
bigRoundedTimerLabel : Element.Color -> List (Element msg) -> Element msg
bigRoundedTimerLabel color content =
    Element.el [ Background.color color, width fill, height fill, Border.rounded 5 ]
        (Element.row [ height fill, centerX, padding 15, spacing 10, Font.size 40 ]
            content
        )


maybePromotionButtons : List Sako.Action -> Element Msg
maybePromotionButtons actions =
    let
        canPromote =
            actions
                |> List.any
                    (\a ->
                        case a of
                            Sako.Promote _ ->
                                True

                            _ ->
                                False
                    )
    in
    if canPromote then
        promotionButtons

    else
        Element.none


promotionButtons : Element Msg
promotionButtons =
    Element.column [ width fill, spacing 5 ]
        [ Element.row [ width fill, spacing 5 ]
            [ bigRoundedButton (Element.rgb255 200 240 200)
                (Just (PlayActionInputStep (Sako.Promote Sako.Queen) |> PlayMsgWrapper))
                [ icon [ centerX ] Solid.chessQueen
                , Element.el [ centerX ] (Element.text "Queen")
                ]
            , bigRoundedButton (Element.rgb255 200 240 200)
                (Just (PlayActionInputStep (Sako.Promote Sako.Knight) |> PlayMsgWrapper))
                [ icon [ centerX ] Solid.chessKnight
                , Element.el [ centerX ] (Element.text "Knight")
                ]
            ]
        , Element.row [ width fill, spacing 5 ]
            [ bigRoundedButton (Element.rgb255 200 240 200)
                (Just (PlayActionInputStep (Sako.Promote Sako.Rook) |> PlayMsgWrapper))
                [ icon [ centerX ] Solid.chessRook
                , Element.el [ centerX ] (Element.text "Rook")
                ]
            , bigRoundedButton (Element.rgb255 200 240 200)
                (Just (PlayActionInputStep (Sako.Promote Sako.Bishop) |> PlayMsgWrapper))
                [ icon [ centerX ] Solid.chessBishop
                , Element.el [ centerX ] (Element.text "Bishop")
                ]
            ]
        ]


maybeVictoryStateInfo : Sako.VictoryState -> Element msg
maybeVictoryStateInfo victoryState =
    case victoryState of
        Sako.Running ->
            Element.none

        Sako.PacoVictory Sako.White ->
            bigRoundedVictoryStateLabel (Element.rgb255 255 215 0)
                [ Element.el [ Font.size 30, centerX ] (Element.text "Paco White")
                ]

        Sako.PacoVictory Sako.Black ->
            bigRoundedVictoryStateLabel (Element.rgb255 255 215 0)
                [ Element.el [ Font.size 30, centerX ] (Element.text "Paco Black")
                ]

        Sako.TimeoutVictory Sako.White ->
            bigRoundedVictoryStateLabel (Element.rgb255 255 215 0)
                [ Element.el [ Font.size 30, centerX ] (Element.text "Paco White")
                , Element.el [ Font.size 20, centerX ] (Element.text "(Timeout)")
                ]

        Sako.TimeoutVictory Sako.Black ->
            bigRoundedVictoryStateLabel (Element.rgb255 255 215 0)
                [ Element.el [ Font.size 30, centerX ] (Element.text "Paco Black")
                , Element.el [ Font.size 20, centerX ] (Element.text "(Timeout)")
                ]


{-| Label that is used for the Victory status.
-}
bigRoundedVictoryStateLabel : Element.Color -> List (Element msg) -> Element msg
bigRoundedVictoryStateLabel color content =
    Element.el [ Background.color color, width fill, Border.rounded 5, Element.alignTop ]
        (Element.column [ height fill, centerX, padding 15, spacing 5 ]
            content
        )


{-| Turns an amount of seconds into a mm:ss label.
-}
timeLabel : Int -> String
timeLabel seconds =
    let
        data =
            distributeSeconds seconds
    in
    (String.fromInt data.minutes |> String.padLeft 2 '0')
        ++ ":"
        ++ (String.fromInt data.seconds |> String.padLeft 2 '0')


distributeSeconds : Int -> { seconds : Int, minutes : Int }
distributeSeconds seconds =
    { seconds = seconds |> modBy 60, minutes = seconds // 60 }



--------------------------------------------------------------------------------
-- Setting up a Paco Ŝako Match ------------------------------------------------
--------------------------------------------------------------------------------


type MatchSetupMsg
    = SetRawMatchId String
    | JoinMatch
    | CreateMatch
    | MatchCreatedOnServer String
    | SetTimeLimit Int
    | SetRawTimeLimit String


type alias MatchSetupModel =
    { rawMatchId : String
    , matchConnectionStatus : MatchConnectionStatus
    , timeLimit : Int
    , rawTimeLimit : String
    }


type MatchConnectionStatus
    = NoMatchConnection
    | MatchConnectionRequested String


initMatchSetupModel : MatchSetupModel
initMatchSetupModel =
    { rawMatchId = ""
    , matchConnectionStatus = NoMatchConnection
    , timeLimit = 300
    , rawTimeLimit = "300"
    }


updateMatchSetup : MatchSetupMsg -> MatchSetupModel -> ( MatchSetupModel, Cmd Msg )
updateMatchSetup msg model =
    case msg of
        SetRawMatchId rawMatchId ->
            ( { model | rawMatchId = rawMatchId }, Cmd.none )

        JoinMatch ->
            joinMatch model

        CreateMatch ->
            createMatch model

        MatchCreatedOnServer newId ->
            joinMatch { model | rawMatchId = newId }

        SetTimeLimit newLimit ->
            ( { model | timeLimit = newLimit, rawTimeLimit = String.fromInt newLimit }, Cmd.none )

        SetRawTimeLimit newRawLimit ->
            ( { model | rawTimeLimit = newRawLimit } |> tryParseRawLimit, Cmd.none )


{-| Parse the rawTimeLimit into an integer and take it over to the time limit if
parsing is successfull.
-}
tryParseRawLimit : MatchSetupModel -> MatchSetupModel
tryParseRawLimit model =
    case String.toInt model.rawTimeLimit of
        Just newLimit ->
            { model | timeLimit = newLimit }

        Nothing ->
            model


joinMatch : MatchSetupModel -> ( MatchSetupModel, Cmd Msg )
joinMatch model =
    ( { model | matchConnectionStatus = MatchConnectionRequested model.rawMatchId }
    , Websocket.send (Websocket.SubscribeToMatch model.rawMatchId)
    )


{-| Requests a new syncronized match from the server.
-}
createMatch : MatchSetupModel -> ( MatchSetupModel, Cmd Msg )
createMatch model =
    let
        timerConfig =
            if model.timeLimit > 0 then
                Just (Timer.secondsConfig { white = model.timeLimit, black = model.timeLimit })

            else
                Nothing
    in
    ( model, postMatchRequest timerConfig (MatchCreatedOnServer >> MatchSetupMsgWrapper) )


{-| Use this to call the "create game" api of the server.
-}
postMatchRequest : Maybe Timer.TimerConfig -> (String -> Msg) -> Cmd Msg
postMatchRequest config onSuccess =
    Http.post
        { url = "/api/create_game"
        , body = Http.jsonBody (encodePostMatchRequest config)
        , expect =
            Http.expectString
                (\response ->
                    case response of
                        Ok key ->
                            onSuccess key

                        Err e ->
                            HttpError e
                )
        }


encodePostMatchRequest : Maybe Timer.TimerConfig -> Value
encodePostMatchRequest timer =
    Encode.object
        [ ( "timer"
          , Maybe.map Timer.encodeConfig timer
                |> Maybe.withDefault Encode.null
          )
        ]


matchSetupUi : Taco -> MatchSetupModel -> Element Msg
matchSetupUi taco model =
    Element.column [ width fill, height fill, Element.scrollbarY ]
        [ Element.html FontAwesome.Styles.css
        , pageHeader taco MatchSetupPage Element.none
        , Element.el [ padding 40, centerX, Font.size 40, Font.bold ] (Element.text "Play Paco Ŝako")
        , matchSetupUiInner model
        ]


matchSetupUiInner : MatchSetupModel -> Element Msg
matchSetupUiInner model =
    Element.row [ width (fill |> Element.maximum 1200), padding 5, spacing 5, centerX ]
        [ joinOnlineMatchUi model
        , setupOnlineMatchUi model
        ]


box : Element.Color -> List (Element Msg) -> Element Msg
box color content =
    Element.el [ width fill, centerX, padding 10, Background.color color, height fill ]
        (Element.column [ width fill, centerX, spacing 7 ]
            content
        )


setupOnlineMatchUi : MatchSetupModel -> Element Msg
setupOnlineMatchUi model =
    box (Element.rgb255 220 230 220)
        [ Element.el [ centerX, Font.size 30 ] (Element.text "Create a new Game")
        , Element.row [ width fill, spacing 7 ]
            [ speedButton
                { buttonIcon = Solid.bolt
                , caption = "Blitz"
                , event = SetTimeLimit 300 |> MatchSetupMsgWrapper
                , selected = model.timeLimit == 300
                }
            , speedButton
                { buttonIcon = Solid.hourglassHalf
                , caption = "Slow"
                , event = SetTimeLimit 1200 |> MatchSetupMsgWrapper
                , selected = model.timeLimit == 1200
                }
            ]
        , Element.row [ width fill, spacing 7 ]
            [ speedButton
                { buttonIcon = Solid.wrench
                , caption = "Custom"
                , event = SetTimeLimit model.timeLimit |> MatchSetupMsgWrapper
                , selected = List.notMember model.timeLimit [ 0, 300, 1200 ]
                }
            , speedButton
                { buttonIcon = Solid.dove
                , caption = "No Timer"
                , event = SetTimeLimit 0 |> MatchSetupMsgWrapper
                , selected = model.timeLimit == 0
                }
            ]
        , Input.text []
            { onChange = SetRawTimeLimit >> MatchSetupMsgWrapper
            , text = model.rawTimeLimit
            , placeholder = Nothing
            , label = Input.labelLeft [ centerY ] (Element.text "Time in seconds")
            }
        , timeLimitLabel model.timeLimit
        , bigRoundedButton (Element.rgb255 200 210 200)
            (Just (CreateMatch |> MatchSetupMsgWrapper))
            [ Element.text "Create Match" ]
        ]


speedButton : { buttonIcon : Icon, caption : String, event : Msg, selected : Bool } -> Element Msg
speedButton config =
    bigRoundedButton (speedButtonColor config.selected)
        (Just config.event)
        [ icon [ centerX ] config.buttonIcon
        , Element.el [ centerX ] (Element.text config.caption)
        ]


speedButtonColor : Bool -> Element.Color
speedButtonColor selected =
    if selected then
        Element.rgb255 180 200 180

    else
        Element.rgb255 200 210 200


{-| A label that translates the amount of seconds into minutes and seconds that
are better readable.
-}
timeLimitLabel : Int -> Element msg
timeLimitLabel seconds =
    let
        data =
            distributeSeconds seconds
    in
    if seconds > 0 then
        Element.text
            (String.fromInt data.minutes
                ++ " Minutes and "
                ++ String.fromInt data.seconds
                ++ " Seconds for each player"
            )

    else
        Element.text "Play without time limit"


joinOnlineMatchUi : MatchSetupModel -> Element Msg
joinOnlineMatchUi model =
    box (Element.rgb255 220 220 230)
        [ Element.el [ centerX, Font.size 30 ] (Element.text "I got an Invite")
        , Input.text [ width fill, EventsCustom.onEnter (JoinMatch |> MatchSetupMsgWrapper) ]
            { onChange = SetRawMatchId >> MatchSetupMsgWrapper
            , text = model.rawMatchId
            , placeholder = Just (Input.placeholder [] (Element.text "Enter Match Id"))
            , label = Input.labelLeft [ centerY ] (Element.text "Match Id")
            }
        , bigRoundedButton (Element.rgb255 200 200 210)
            (Just (JoinMatch |> MatchSetupMsgWrapper))
            [ Element.text "Join Game" ]
        ]


{-| A button that is implemented via a vertical column.
-}
bigRoundedButton : Element.Color -> Maybe msg -> List (Element msg) -> Element msg
bigRoundedButton color event content =
    Input.button [ Background.color color, width fill, height fill, Border.rounded 5 ]
        { onPress = event
        , label = Element.column [ height fill, centerX, padding 15, spacing 10 ] content
        }
