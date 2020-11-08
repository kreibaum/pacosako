module Pages.Top exposing (Model, Msg, Params, page)

import Animation exposing (Timeline)
import Api.Ai
import Api.Backend
import Api.Ports as Ports
import Api.Websocket as Websocket exposing (CurrentMatchState)
import Arrow exposing (Arrow)
import Browser
import Browser.Events
import CastingDeco
import Element exposing (..)
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
import I18n.Strings as I18n exposing (Language(..), t)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import List.Extra as List
import Maybe.Extra as Maybe
import Pieces
import Pivot as P exposing (Pivot)
import PositionView exposing (BoardDecoration(..), DragPieceData, DragState, DraggingPieces(..), Highlight(..), OpaqueRenderData, coordinateOfTile, nextHighlight)
import Reactive exposing (Device(..))
import RemoteData exposing (WebData)
import Result.Extra as Result
import Sako exposing (Piece, Tile(..))
import SaveState exposing (SaveState(..), saveStateId, saveStateModify, saveStateStored)
import Spa.Document exposing (Document)
import Spa.Page as Page
import Spa.Url exposing (Url)
import Svg exposing (Svg)
import Svg.Attributes as SvgA
import Svg.Custom as Svg
import Time exposing (Posix)
import Timer
import Tutorial


type alias Params =
    ()


type alias Model =
    { taco : Taco
    , page : Page
    , play : PlayModel
    , matchSetup : MatchSetupModel
    , editor : EditorModel
    , login : LoginModel
    , language : Language

    -- , url : Url Params
    }


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
    | WindowResize Int Int
    | SetLanguage Language


page : Page.Page Params Model Msg
page =
    Page.application
        { init = \shared params -> init shared.flags
        , update = update
        , view = view
        , subscriptions = subscriptions
        , save = always identity
        , load = \_ model -> ( model, Cmd.none )
        }



-- VIEW
-- view : Model -> Html Msg
-- view model =
--     Element.layout [ height fill, Element.scrollbarY ] (globalUi model)


view : Model -> Document Msg
view model =
    { title = "Paco Ŝako"
    , body = [ globalUi model ]
    }



--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- All of my old code from Main.elm --------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------


type Page
    = PlayPage
    | MatchSetupPage
    | EditorPage
    | LoginPage
    | TutorialPage


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


type alias EditorModel =
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
    , shareStatus : Websocket.ShareStatus
    , rawShareKey : String
    , showExportOptions : Bool
    , castingDeco : CastingDeco.Model
    , inputMode : Maybe CastingDeco.InputMode
    }


type PositionParseResult
    = NoInput
    | ParseError String
    | ParseSuccess Sako.Position


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


{-| Messages that may only affect data in the position editor page.
-}
type EditorMsg
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
    | StartSharing
    | GotSharingResult Websocket.ShareStatus
    | InputRawShareKey String
    | WebsocketConnect String
    | SetExportOptionsVisible Bool
    | SetInputModeEditor (Maybe CastingDeco.InputMode)
    | ClearDecoTilesEditor
    | ClearDecoArrowsEditor


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


initialEditor : ( Int, Int ) -> EditorModel
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
    , shareStatus = Websocket.NotShared
    , rawShareKey = ""
    , showExportOptions = Basics.False
    , castingDeco = CastingDeco.initModel
    , inputMode = Nothing
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
      , play = initPlayModel (parseWindowSize flags)
      , matchSetup = initMatchSetupModel
      , editor = initialEditor (parseWindowSize flags)
      , login = initialLogin
      , language = I18n.English
      }
    , Cmd.batch
        [ Api.Backend.getCurrentLogin HttpError
            (Maybe.map LoginSuccess >> Maybe.withDefault LogoutSuccess)
        , refreshRecentGames
        ]
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
            ( model, Ports.logToConsole (Api.Backend.describeError error) )

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

        WindowResize width height ->
            let
                oldEditor =
                    model.editor

                oldPlay =
                    model.play
            in
            ( { model
                | editor = { oldEditor | windowSize = ( width, height ) }
                , play = { oldPlay | windowSize = ( width, height ) }
              }
            , Cmd.none
            )

        SetLanguage lang ->
            ( { model | language = lang }, Cmd.none )


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
                Nothing ->
                    let
                        dragData =
                            { start = mouse, current = mouse }
                    in
                    case mouse.tile of
                        Just tile ->
                            clickStart tile { model | drag = Just dragData }

                        Nothing ->
                            ( model, Cmd.none )

                Just mode ->
                    ( { model | castingDeco = CastingDeco.mouseDown mode mouse model.castingDeco }, Cmd.none )

        MouseMove mouse ->
            case model.inputMode of
                Nothing ->
                    handleMouseMove mouse model

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
                            clickRelease dragData.start dragData.current { model | drag = Nothing }

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

        SavePosition position saveState ->
            ( model
            , Api.Backend.postSave position
                saveState
                HttpError
                (EditorMsgWrapper << PositionSaveSuccess)
            )

        PositionSaveSuccess data ->
            ( { model | saveState = saveStateStored data.id model.saveState }, Cmd.none )

        RequestRandomPosition ->
            ( model, Api.Backend.getRandomPosition HttpError (EditorMsgWrapper << GotRandomPosition) )

        GotRandomPosition newPosition ->
            ( { model | game = addHistoryState newPosition model.game }
                |> animateToCurrentPosition
            , Cmd.none
            )

        RequestAnalysePosition position ->
            ( model, Api.Backend.postAnalysePosition position HttpError (EditorMsgWrapper << GotAnalysePosition) )

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

        SetInputModeEditor newMode ->
            ( { model | inputMode = newMode }, Cmd.none )

        ClearDecoTilesEditor ->
            ( { model | castingDeco = CastingDeco.clearTiles model.castingDeco }, Cmd.none )

        ClearDecoArrowsEditor ->
            ( { model | castingDeco = CastingDeco.clearArrows model.castingDeco }, Cmd.none )


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
            deleteSelectedPiece model

        "Backspace" ->
            deleteSelectedPiece model

        _ ->
            ( model, Cmd.none )


deleteSelectedPiece : EditorModel -> ( EditorModel, Cmd Msg )
deleteSelectedPiece model =
    let
        ( newTool, outMsg ) =
            updateSmartToolDelete (P.getC model.game) model.smartTool
    in
    handleToolOutputMsg outMsg
        { model | smartTool = newTool }


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
        , Browser.Events.onKeyUp (Decode.map KeyUp decodeKeyStroke)
            |> Sub.map EditorMsgWrapper
        , Ports.responseSvgNodeContent SvgReadyForDownload
            |> Sub.map EditorMsgWrapper
        , Websocket.listen WebsocketMsg WebsocketErrorMsg
        , Animation.subscription model.editor.timeline AnimationTick
        , Animation.subscription model.play.timeline (PlayMsgAnimationTick >> PlayMsgWrapper)
        , Time.every 1000 UpdateNow
        , Api.Ai.subscribeMoveFromAi (PlayMsgWrapper AiCrashed) (MoveFromAi >> PlayMsgWrapper)
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
            ( loginPageModel
            , Api.Backend.postLoginPassword
                { username = loginPageModel.usernameRaw
                , password = loginPageModel.passwordRaw
                }
                HttpError
                LoginSuccess
            )

        Logout ->
            ( loginPageModel, Api.Backend.getLogout HttpError (\() -> LogoutSuccess) )


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

        TutorialPage ->
            tutorialUi model.taco model.language


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
        , pageHeaderButton [] { currentPage = currentPage, targetPage = TutorialPage, caption = "Tutorial" }
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
    , nodeId = Just sakoEditorId
    , decoration = toolDecoration editor
    , dragPieceData = dragPieceData editor
    , mouseDown = Just MouseDown
    , mouseUp = Just MouseUp
    , mouseMove = Just MouseMove
    , additionalSvg = Nothing
    , replaceViewport = Nothing
    }


castingDecoMappers : { tile : Tile -> BoardDecoration, arrow : Arrow -> BoardDecoration }
castingDecoMappers =
    { tile = CastingHighlight
    , arrow = CastingArrow
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
    in
    ([ selectionHighlight
     , hoverHighlight
     , dragPiece
     ]
        |> List.filterMap identity
    )
        ++ CastingDeco.toDecoration castingDecoMappers model.castingDeco


dragPieceData : EditorModel -> List DragPieceData
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
         , shareButton model |> Element.map EditorMsgWrapper
         , shareInput model |> Element.map EditorMsgWrapper
         , CastingDeco.configView castingDecoMessagesEditor model.inputMode model.castingDeco
         ]
            ++ exportOptions
        )


castingDecoMessagesEditor : CastingDeco.Messages Msg
castingDecoMessagesEditor =
    { setInputMode = EditorMsgWrapper << SetInputModeEditor
    , clearTiles = EditorMsgWrapper ClearDecoTilesEditor
    , clearArrows = EditorMsgWrapper ClearDecoArrowsEditor
    }


hideExportOptions : Element Msg
hideExportOptions =
    Input.button [] { onPress = Just (EditorMsgWrapper (SetExportOptionsVisible False)), label = Element.text "Hide Export Options" }


showExportOptions : Element Msg
showExportOptions =
    Input.button [] { onPress = Just (EditorMsgWrapper (SetExportOptionsVisible True)), label = Element.text "Show Export Options" }


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
-- Tutorial page ---------------------------------------------------------------
--------------------------------------------------------------------------------


tutorialUi : Taco -> Language -> Element Msg
tutorialUi taco lang =
    Element.column [ width fill, height fill, Element.scrollbarY ]
        [ Element.html FontAwesome.Styles.css
        , pageHeader taco TutorialPage Element.none
        , Tutorial.tutorialPage lang SetLanguage
        ]



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
    , windowSize : ( Int, Int )

    -- later: , preview : Maybe Sako.Position
    , timeline : Timeline OpaqueRenderData
    , focus : Maybe Tile
    , dragState : DragState
    , castingDeco : CastingDeco.Model
    , inputMode : Maybe CastingDeco.InputMode
    }


initPlayModel : ( Int, Int ) -> PlayModel
initPlayModel windowSize =
    { board = Sako.initialPosition
    , windowSize = windowSize
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
    , dragState = Nothing
    , castingDeco = CastingDeco.initModel
    , inputMode = Nothing
    }


type PlayMsg
    = PlayActionInputStep Sako.Action
    | PlayRollback
    | PlayMsgAnimationTick Posix
    | PlayMouseDown BoardMousePosition
    | PlayMouseUp BoardMousePosition
    | PlayMouseMove BoardMousePosition
    | SetInputModePlay (Maybe CastingDeco.InputMode)
    | ClearDecoTilesPlay
    | ClearDecoArrowsPlay
    | MoveFromAi Sako.Action
    | RequestAiMove
    | AiCrashed


castingDecoMessagesPlay : CastingDeco.Messages Msg
castingDecoMessagesPlay =
    { setInputMode = PlayMsgWrapper << SetInputModePlay
    , clearTiles = PlayMsgWrapper ClearDecoTilesPlay
    , clearArrows = PlayMsgWrapper ClearDecoArrowsPlay
    }


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

        PlayMouseDown pos ->
            case model.inputMode of
                Nothing ->
                    updateMouseDown pos model

                Just mode ->
                    ( { model | castingDeco = CastingDeco.mouseDown mode pos model.castingDeco }, Cmd.none )

        PlayMouseUp pos ->
            case model.inputMode of
                Nothing ->
                    updateMouseUp pos model

                Just mode ->
                    ( { model | castingDeco = CastingDeco.mouseUp mode pos model.castingDeco }, Cmd.none )

        PlayMouseMove pos ->
            case model.inputMode of
                Nothing ->
                    updateMouseMove pos model

                Just mode ->
                    ( { model | castingDeco = CastingDeco.mouseMove mode pos model.castingDeco }, Cmd.none )

        SetInputModePlay inputMode ->
            ( { model | inputMode = inputMode }, Cmd.none )

        ClearDecoTilesPlay ->
            ( { model | castingDeco = CastingDeco.clearTiles model.castingDeco }, Cmd.none )

        ClearDecoArrowsPlay ->
            ( { model | castingDeco = CastingDeco.clearArrows model.castingDeco }, Cmd.none )

        MoveFromAi action ->
            updateActionInputStep action model

        RequestAiMove ->
            ( model, Api.Ai.requestMoveFromAi )

        AiCrashed ->
            ( model, Ports.logToConsole "Ai Crashed" )


legalActionAt : CurrentMatchState -> Tile -> Maybe Sako.Action
legalActionAt state tile =
    state.legalActions
        |> List.filter (\action -> Sako.actionTile action == Just tile)
        -- There can never be two actions on the same square, so this is safe.
        |> List.head


liftActionAt : CurrentMatchState -> Tile -> Maybe Sako.Action
liftActionAt state tile =
    state.legalActions
        |> List.filter (\action -> Sako.actionTile action == Just tile)
        |> List.filterMap
            (\a ->
                case a of
                    Sako.Lift _ ->
                        Just a

                    _ ->
                        Nothing
            )
        -- There can never be two actions on the same square, so this is safe.
        |> List.head


{-| Call this method do execute a lift action and initialize drag an drop.
Only call it, when you have checked, that there is a legal lift action at the
clicked tile.
-}
updateMouseDown : BoardMousePosition -> PlayModel -> ( PlayModel, Cmd Msg )
updateMouseDown pos model =
    -- Check if there is a piece we can lift at this position.
    case Maybe.andThen (liftActionAt model.currentState) pos.tile of
        Just action ->
            updateActionInputStep action
                { model
                    | dragState = Just { start = pos, current = pos }
                }

        Nothing ->
            updateTryRegrabLiftedPiece pos model


{-| Checks if there is already a lifted piece at the given position and allows
us to take hold of it again.
-}
updateTryRegrabLiftedPiece : BoardMousePosition -> PlayModel -> ( PlayModel, Cmd Msg )
updateTryRegrabLiftedPiece pos model =
    let
        liftedPieces =
            model.board.liftedPieces
                |> List.head
                |> Maybe.map (\p -> p.position)
    in
    if liftedPieces == pos.tile && pos.tile /= Nothing then
        ( { model
            | dragState = Just { start = pos, current = pos }
            , timeline =
                Animation.interrupt
                    (renderPlayViewDragging { start = pos, current = pos } model)
                    model.timeline
          }
        , Cmd.none
        )

    else
        ( model, Cmd.none )


updateMouseUp : BoardMousePosition -> PlayModel -> ( PlayModel, Cmd Msg )
updateMouseUp pos model =
    case Maybe.andThen (legalActionAt model.currentState) pos.tile of
        -- Check if the position is an allowed action.
        Just action ->
            updateActionInputStep action { model | dragState = Nothing }

        Nothing ->
            ( { model
                | dragState = Nothing
                , timeline =
                    Animation.queue
                        ( Animation.milliseconds 200, PositionView.renderStatic model.board )
                        model.timeline
              }
            , Cmd.none
            )


updateMouseMove : BoardMousePosition -> PlayModel -> ( PlayModel, Cmd Msg )
updateMouseMove mousePosition model =
    case model.dragState of
        Just dragState ->
            updateMouseMoveDragging
                { dragState
                    | current = mousePosition
                }
                model

        Nothing ->
            ( model, Cmd.none )


updateMouseMoveDragging :
    { start : BoardMousePosition
    , current : BoardMousePosition
    }
    -> PlayModel
    -> ( PlayModel, Cmd Msg )
updateMouseMoveDragging dragState model =
    ( { model
        | dragState =
            Just dragState
        , timeline =
            Animation.interrupt
                (renderPlayViewDragging dragState model)
                model.timeline
      }
    , Cmd.none
    )


renderPlayViewDragging :
    { start : BoardMousePosition
    , current : BoardMousePosition
    }
    -> PlayModel
    -> OpaqueRenderData
renderPlayViewDragging dragState model =
    let
        dragDelta =
            Svg.Coord
                (dragState.current.x - dragState.start.x)
                (dragState.current.y - dragState.start.y)
    in
    PositionView.render
        -- There is a bunch of info that is only in here for the
        -- design page which still needs more renderer refactoring.
        -- Note that the highlight is not even used.
        { highlight = Nothing
        , dragStartTile = Nothing
        , dragDelta = Just dragDelta
        , hover = Nothing
        , draggingPieces = DraggingPiecesNormal []
        }
        model.board


{-| Add the given action to the list of all actions taken and sends it to the
server for confirmation. Will also trigger an animation.
-}
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
    , Cmd.batch
        [ Websocket.DoAction
            { key = Maybe.withDefault "" model.subscription
            , action = action
            }
            |> Websocket.send
        , case action of
            Sako.Place _ ->
                Ports.playSound ()

            Sako.Lift _ ->
                Cmd.none

            Sako.Promote _ ->
                Cmd.none
        ]
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
    case Reactive.classify model.windowSize of
        LandscapeDevice ->
            playUiLandscape taco model

        PortraitDevice ->
            playUiPortrait taco model


playUiLandscape : Taco -> PlayModel -> Element Msg
playUiLandscape taco model =
    Element.column [ width fill, height fill, Element.scrollbarY ]
        [ Element.html FontAwesome.Styles.css
        , pageHeader taco PlayPage Element.none
        , Element.row
            [ width fill, height fill, Element.scrollbarY ]
            [ playPositionView taco model
            , playModeSidebar taco model
            ]
        ]


playUiPortrait : Taco -> PlayModel -> Element Msg
playUiPortrait taco model =
    Element.column [ width fill, height fill ]
        [ Element.html FontAwesome.Styles.css
        , pageHeader taco PlayPage Element.none
        , Element.column
            [ width fill, height fill ]
            [ playPositionView taco model
            , playModeSidebar taco model
            ]
        ]


playPositionView : Taco -> PlayModel -> Element Msg
playPositionView taco play =
    Element.el [ width fill, height fill ]
        (PositionView.viewTimeline
            { colorScheme = taco.colorScheme
            , nodeId = Just sakoEditorId
            , decoration = playDecoration play
            , dragPieceData = []
            , mouseDown = Just (PlayMouseDown >> PlayMsgWrapper)
            , mouseUp = Just (PlayMouseUp >> PlayMsgWrapper)
            , mouseMove = Just (PlayMouseMove >> PlayMsgWrapper)
            , additionalSvg = playTimerSvg taco.now play
            , replaceViewport = playTimerReplaceViewport play
            }
            play.timeline
        )


playDecoration : PlayModel -> List PositionView.BoardDecoration
playDecoration play =
    (play.currentState.legalActions
        |> List.filterMap actionDecoration
    )
        ++ playViewHighlight play
        ++ CastingDeco.toDecoration castingDecoMappers play.castingDeco


actionDecoration : Sako.Action -> Maybe PositionView.BoardDecoration
actionDecoration action =
    case action of
        Sako.Place tile ->
            Just (PositionView.PlaceTarget tile)

        _ ->
            Nothing


{-| Decides what kind of highlight should be shown when rendering the play view.
-}
playViewHighlight : PlayModel -> List BoardDecoration
playViewHighlight model =
    let
        tile =
            Maybe.andThen (\dragState -> dragState.current.tile) model.dragState

        dropAction =
            tile
                |> Maybe.andThen (legalActionAt model.currentState)
    in
    Maybe.map2 (\t _ -> [ HighlightTile ( t, HighlightBoth ) ]) tile dropAction
        |> Maybe.withDefault []


playTimerSvg : Posix -> PlayModel -> Maybe (Svg a)
playTimerSvg now model =
    model.currentState.timer
        |> Maybe.map (justPlayTimerSvg now model)


justPlayTimerSvg : Posix -> PlayModel -> Timer.Timer -> Svg a
justPlayTimerSvg now model timer =
    let
        viewData =
            Timer.render model.currentState.controllingPlayer now timer
    in
    Svg.g []
        [ timerTagSvg
            { caption = timeLabel viewData.secondsLeftWhite
            , player = Sako.White
            , at = Svg.Coord 0 820
            }
        , timerTagSvg
            { caption = timeLabel viewData.secondsLeftBlack
            , player = Sako.Black
            , at = Svg.Coord 0 -70
            }
        ]


{-| Creates a little rectangle with a text which can be used to display the
timer for one player. Picks colors automatically based on the player.
-}
timerTagSvg :
    { caption : String
    , player : Sako.Color
    , at : Svg.Coord
    }
    -> Svg msg
timerTagSvg data =
    let
        ( backgroundColor, textColor ) =
            case data.player of
                Sako.White ->
                    ( "#eee", "#333" )

                Sako.Black ->
                    ( "#333", "#eee" )
    in
    Svg.g [ Svg.translate data.at ]
        [ Svg.rect [ SvgA.width "200", SvgA.height "50", SvgA.fill backgroundColor ] []
        , timerTextSvg (SvgA.fill textColor) data.caption
        ]


timerTextSvg : Svg.Attribute msg -> String -> Svg msg
timerTextSvg fill caption =
    Svg.text_
        [ SvgA.style "text-anchor:middle;font-size:50px;pointer-events:none;-moz-user-select: none;-webkit-user-select: none;dominant-baseline:middle"
        , SvgA.x "100"
        , SvgA.y "30"
        , fill
        ]
        [ Svg.text caption ]


playTimerReplaceViewport :
    PlayModel
    ->
        Maybe
            { x : Float
            , y : Float
            , width : Float
            , height : Float
            }
playTimerReplaceViewport play =
    if Maybe.isNothing play.currentState.timer then
        Nothing

    else
        Just
            { x = -70
            , y = -80
            , width = 900
            , height = 960
            }


playModeSidebar : Taco -> PlayModel -> Element Msg
playModeSidebar taco model =
    Element.column [ spacing 5, padding 20, height fill ]
        [ gameCodeLabel model.subscription
        , bigRoundedButton (Element.rgb255 220 220 220)
            (Just (PlayRollback |> PlayMsgWrapper))
            [ Element.text "Restart Move" ]
            |> Element.el [ width fill ]
        , maybePromotionButtons model.currentState.legalActions
        , maybeVictoryStateInfo model.currentState.gameState
        , CastingDeco.configView castingDecoMessagesPlay model.inputMode model.castingDeco

        -- , Input.button []
        --     { onPress = Just (PlayMsgWrapper RequestAiMove)
        --     , label = Element.text "Request Ai Move"
        --     }
        ]


gameCodeLabel : Maybe String -> Element msg
gameCodeLabel subscription =
    case subscription of
        Just id ->
            Element.column [ width fill, spacing 5 ]
                [ bigRoundedTimerLabel (Element.rgb255 220 220 220) [ Element.text id ]
                , Element.text "Share this id with a friend."
                ]

        Nothing ->
            Element.text "Not connected"


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
    | RefreshRecentGames
    | GotRecentGames (List String)
    | ErrorRecentGames Http.Error


type alias MatchSetupModel =
    { rawMatchId : String
    , matchConnectionStatus : MatchConnectionStatus
    , timeLimit : Int
    , rawTimeLimit : String
    , recentGames : WebData (List String)
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
    , recentGames = RemoteData.Loading
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

        GotRecentGames games ->
            ( { model | recentGames = RemoteData.Success games }, Cmd.none )

        ErrorRecentGames error ->
            ( { model | recentGames = RemoteData.Failure error }, Cmd.none )

        RefreshRecentGames ->
            ( { model | recentGames = RemoteData.Loading }, refreshRecentGames )


refreshRecentGames : Cmd Msg
refreshRecentGames =
    Api.Backend.getRecentGameKeys
        (ErrorRecentGames >> MatchSetupMsgWrapper)
        (GotRecentGames >> MatchSetupMsgWrapper)


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
    ( model, Api.Backend.postMatchRequest timerConfig HttpError (MatchCreatedOnServer >> MatchSetupMsgWrapper) )


matchSetupUi : Taco -> MatchSetupModel -> Element Msg
matchSetupUi taco model =
    Element.column [ width fill, height fill, Element.scrollbarY ]
        [ Element.html FontAwesome.Styles.css
        , pageHeader taco MatchSetupPage Element.none
        , Element.el [ padding 40, centerX, Font.size 40 ] (Element.text "Play Paco Ŝako")
        , matchSetupUiInner model
        ]


matchSetupUiInner : MatchSetupModel -> Element Msg
matchSetupUiInner model =
    Element.column [ width (fill |> Element.maximum 1200), padding 5, spacing 5, centerX ]
        [ Element.row [ width fill, spacing 5, centerX ]
            [ joinOnlineMatchUi model
            , setupOnlineMatchUi model
            ]
        , recentGamesList model.recentGames
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


recentGamesList : WebData (List String) -> Element Msg
recentGamesList data =
    case data of
        RemoteData.NotAsked ->
            Input.button [ padding 10 ]
                { onPress = Just (RefreshRecentGames |> MatchSetupMsgWrapper)
                , label = Element.text "Search for recent games"
                }

        RemoteData.Loading ->
            Element.el [ padding 10 ]
                (Element.text "Searching for recent games...")

        RemoteData.Failure _ ->
            Input.button [ padding 10 ]
                { onPress = Just (RefreshRecentGames |> MatchSetupMsgWrapper)
                , label = Element.text "Error while searching for games! Try again?"
                }

        RemoteData.Success games ->
            recentGamesListSuccess games


recentGamesListSuccess : List String -> Element Msg
recentGamesListSuccess games =
    if List.isEmpty games then
        Input.button [ padding 10 ]
            { onPress = Just (RefreshRecentGames |> MatchSetupMsgWrapper)
            , label = Element.text "There were no games recently started. Check again?"
            }

    else
        Element.row [ width fill, spacing 5 ]
            (List.map recentGamesListSuccessOne games
                ++ [ Input.button
                        [ padding 10
                        , Background.color (Element.rgb 0.9 0.9 0.9)
                        ]
                        { onPress = Just (RefreshRecentGames |> MatchSetupMsgWrapper)
                        , label = Element.text "Refresh"
                        }
                   ]
            )


recentGamesListSuccessOne : String -> Element Msg
recentGamesListSuccessOne game =
    Input.button
        [ padding 10
        , Background.color (Element.rgb 0.9 0.9 0.9)
        ]
        { onPress = Just (SetRawMatchId game |> MatchSetupMsgWrapper)
        , label = Element.text game
        }
