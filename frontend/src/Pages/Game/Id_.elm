module Pages.Game.Id_ exposing (Model, Msg, Params, page)

import Ai exposing (AiState(..))
import Animation exposing (Timeline)
import Api.DecoderGen exposing (LegalActionsDeterminedData)
import Api.Decoders exposing (ControlLevel(..), CurrentMatchState, LegalActions(..), PublicUserData, getActionList)
import Api.EncoderGen
import Api.MessageGen
import Api.Ports
import Api.Websocket
import Arrow
import Browser.Dom
import Browser.Events
import CastingDeco
import Colors
import Components exposing (btn, colorButton, isSelectedIf, viewButton, withMsgIf)
import Custom.Element exposing (icon, showIf)
import Custom.Events exposing (BoardMousePosition, KeyBinding, fireMsg, forKey)
import Custom.List
import Effect exposing (Effect)
import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Fen
import FontAwesome.Icon exposing (Icon)
import FontAwesome.Solid as Solid
import Gen.Route as Route
import Header
import Json.Decode as Decode
import Json.Encode as Encode
import Maybe.Extra as Maybe
import Page
import PositionView exposing (BoardDecoration(..), DragState, DraggingPieces(..), Highlight(..), OpaqueRenderData)
import Process
import Reactive exposing (DeviceOrientation(..))
import Request
import Sako
import Shared
import Svg exposing (Svg)
import Svg.Custom as Svg exposing (BoardRotation(..))
import Svg.PlayerLabel exposing (DataRequiredForPlayers)
import Svg.TimerGraphic
import Task
import Tile exposing (Tile(..))
import Time exposing (Posix)
import Translations as T
import Url
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared { params, url } =
    Page.advanced
        { init = init params url
        , update = update shared
        , subscriptions = subscriptions
        , view = view shared
        }



-- INIT


type alias Params =
    { id : String }


type alias Model =
    { board : Sako.Position
    , gameKey : String
    , currentState : CurrentMatchState
    , timeline : Timeline OpaqueRenderData
    , focus : Maybe Tile
    , dragState : DragState
    , castingDeco : CastingDeco.Model
    , inputMode : Maybe CastingDeco.InputMode
    , rotation : BoardRotation
    , gameUrl : Url.Url
    , timeDriftMillis : Float
    , windowHeight : Int
    , visibleHeaderSize : Int
    , elementHeight : Int
    }


init : Params -> Url.Url -> ( Model, Effect Msg )
init params url =
    ( { board = Sako.initialPosition
      , gameKey = params.id
      , currentState =
            { key = ""
            , actionHistory = []
            , setupOptions = Sako.dummySetupOptions
            , canRollback = False
            , legalActions = Api.Decoders.ActionsNotLoaded
            , isRollback = False
            , controllingPlayer = Sako.White
            , timer = Nothing
            , gameState = Sako.Running
            , whitePlayer = Nothing
            , blackPlayer = Nothing
            , whiteControl = LockedByOther
            , blackControl = LockedByOther
            }
      , timeline = Animation.init (PositionView.renderStatic WhiteBottom Sako.initialPosition)
      , focus = Nothing
      , dragState = Nothing
      , castingDeco = CastingDeco.initModel
      , inputMode = Nothing
      , rotation = WhiteBottom
      , gameUrl = url
      , timeDriftMillis = 0
      , windowHeight = 500
      , visibleHeaderSize = 0
      , elementHeight = 500
      }
    , Cmd.batch
        [ -- This is not really nice, but we want to give the websocket time to
          -- connect. This is why we wait five seconds.
          -- May be better to move this into typescript.
          -- But when you do this you need to also move the time drift to a shared
          -- model member, otherwise it won't be available when you start on
          -- the main page and then navigate to a game.
          Process.sleep 5000
            |> Task.andThen (\() -> Time.now)
            |> Task.perform (\now -> TimeDriftRequestTrigger { send = now })
        , Browser.Dom.getViewport
            |> Task.perform (\data -> SetWindowHeight (round data.viewport.height))
        , fetchHeaderSize
        , Encode.object [ ( "key", Encode.string params.id ) ]
            |> Api.MessageGen.subscribeToMatch
        ]
        |> Effect.fromCmd
    )



-- UPDATE


type Msg
    = Promote Sako.Type
    | Rollback
    | AnimationTick Posix
    | MouseDown BoardMousePosition
    | MouseUp BoardMousePosition
    | MouseMove BoardMousePosition
    | SetInputMode (Maybe CastingDeco.InputMode)
    | ClearDecoTiles
    | ClearDecoArrows
    | ClearDecoComplete
    | SetRotation BoardRotation
    | WebsocketMsg Api.Websocket.ServerMessage
    | WebsocketErrorMsg Decode.Error
    | CopyToClipboard String
    | WebsocketStatusChange Api.Websocket.WebsocketConnectionState
    | ToShared Shared.Msg
    | TimeDriftRequestTrigger { send : Posix }
    | TimeDriftResponseTriple { send : Posix, bounced : Posix, back : Posix }
    | SetWindowHeight Int
    | FetchHeaderSize
    | SetVisibleHeaderSize { header : Int, elementHeight : Int }
    | PortError String
    | LegalActionsResponse LegalActionsDeterminedData
    | DetermineAiMove
    | AiStateUpdated
    | AiMoveResponse (List Sako.Action)


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    case msg of
        Promote pieceType ->
            updateActionInputStep shared (Sako.Promote pieceType) model

        AnimationTick now ->
            ( { model | timeline = Animation.tick now model.timeline }, Effect.none )

        Rollback ->
            ( model
            , Api.Websocket.send (Api.Websocket.Rollback model.gameKey) |> Effect.fromCmd
            )

        MouseDown pos ->
            case model.inputMode of
                Nothing ->
                    if isCurrentSideControlledByPlayer model then
                        updateMouseDown shared pos model

                    else
                        ( model, Effect.none )

                Just mode ->
                    ( { model | castingDeco = CastingDeco.mouseDown mode pos model.castingDeco }, Effect.none )

        MouseUp pos ->
            case model.inputMode of
                Nothing ->
                    if isCurrentSideControlledByPlayer model then
                        updateMouseUp shared pos model

                    else
                        ( model, Effect.none )

                Just mode ->
                    ( { model | castingDeco = CastingDeco.mouseUp mode pos model.castingDeco }, Effect.none )

        MouseMove pos ->
            case model.inputMode of
                Nothing ->
                    if isCurrentSideControlledByPlayer model then
                        updateMouseMove pos model

                    else
                        ( model, Effect.none )

                Just mode ->
                    ( { model | castingDeco = CastingDeco.mouseMove mode pos model.castingDeco }, Effect.none )

        SetInputMode inputMode ->
            ( { model | inputMode = inputMode }, Effect.none )

        ClearDecoTiles ->
            ( { model | castingDeco = CastingDeco.clearTiles model.castingDeco }, Effect.none )

        ClearDecoArrows ->
            ( { model | castingDeco = CastingDeco.clearArrows model.castingDeco }, Effect.none )

        ClearDecoComplete ->
            ( { model | castingDeco = CastingDeco.initModel }, Effect.none )

        SetRotation rotation ->
            ( setRotation rotation model, Effect.none )

        WebsocketMsg serverMessage ->
            updateWebsocket shared serverMessage model

        WebsocketErrorMsg error ->
            ( model, Api.Ports.logToConsole (Decode.errorToString error) |> Effect.fromCmd )

        CopyToClipboard text ->
            ( model, Api.Ports.copy text |> Effect.fromCmd )

        WebsocketStatusChange status ->
            ( model
            , case status of
                Api.Websocket.WebsocketConnected ->
                    Encode.object [ ( "key", Encode.string model.gameKey ) ]
                        |> Api.MessageGen.subscribeToMatch
                        |> Effect.fromCmd

                _ ->
                    Effect.none
            )

        ToShared outMsg ->
            ( model, Effect.fromShared outMsg )

        TimeDriftRequestTrigger { send } ->
            ( model, Api.Websocket.send (Api.Websocket.TimeDriftCheck send) |> Effect.fromCmd )

        TimeDriftResponseTriple data ->
            let
                clientTimeAverage =
                    (toFloat (Time.posixToMillis data.send) + toFloat (Time.posixToMillis data.back)) / 2

                clientDrift =
                    clientTimeAverage - toFloat (Time.posixToMillis data.bounced)
            in
            ( { model | timeDriftMillis = clientDrift }
            , Api.Ports.logToConsole
                ("Time drift determined as "
                    ++ String.fromFloat clientDrift
                    ++ ". { send = "
                    ++ String.fromInt (Time.posixToMillis data.send)
                    ++ ", bounced = "
                    ++ String.fromInt (Time.posixToMillis data.bounced)
                    ++ ", back = "
                    ++ String.fromInt (Time.posixToMillis data.back)
                    ++ " }"
                )
                |> Effect.fromCmd
            )

        SetWindowHeight h ->
            ( { model | windowHeight = h }, Effect.none )

        FetchHeaderSize ->
            ( model
            , fetchHeaderSize |> Effect.fromCmd
            )

        SetVisibleHeaderSize { header, elementHeight } ->
            if model.visibleHeaderSize == header && model.elementHeight == elementHeight then
                ( model, Effect.none )

            else
                -- Here we have to do some magic to prevent flickering.
                -- Basically whenever we would flicker, this picks the middle of the states and becomes stable.
                ( { model | visibleHeaderSize = header, elementHeight = elementHeight }, Effect.none )

        PortError error ->
            ( model, Api.Ports.logToConsole error |> Effect.fromCmd )

        LegalActionsResponse { inputActionCount, legalActions, canRollback, controllingPlayer } ->
            let
                currentState =
                    model.currentState
            in
            if List.length currentState.actionHistory == inputActionCount then
                { model
                    | currentState =
                        { currentState
                            | legalActions = Api.Decoders.ActionsLoaded legalActions
                            , canRollback = canRollback
                            , controllingPlayer = controllingPlayer
                        }
                }
                    |> triggerAiMoveIfNecessary shared

            else
                ( model, Effect.none )

        DetermineAiMove ->
            determineAiMove model

        AiStateUpdated ->
            triggerAiMoveIfNecessary shared model

        -- TODO: This can't deal with two actions coming in at once!
        -- https://github.com/kreibaum/pacosako/issues/123
        AiMoveResponse actions ->
            let
                action =
                    List.head actions |> Maybe.withDefault (Sako.Promote Sako.Queen)
            in
            updateActionInputStep shared action model


fetchHeaderSize : Cmd Msg
fetchHeaderSize =
    Browser.Dom.getElement "sako-editor"
        |> Task.attempt
            (\res ->
                case res of
                    Ok data ->
                        SetVisibleHeaderSize
                            { header = max (round (data.element.y - data.viewport.y)) 0
                            , elementHeight = round data.element.height
                            }

                    Err _ ->
                        SetVisibleHeaderSize { header = 0, elementHeight = 0 }
            )


addActionToCurrentMatchState : Sako.Action -> CurrentMatchState -> CurrentMatchState
addActionToCurrentMatchState action state =
    { state
        | actionHistory = state.actionHistory ++ [ action ]
        , legalActions = Api.Decoders.ActionsNotLoaded
        , canRollback = False
    }


{-| This function decides whether interacting with the board in normal mode
should be allowed. This prevents the player from lifting pieces when it isn't
actually their turn.
-}
isCurrentSideControlledByPlayer : Model -> Bool
isCurrentSideControlledByPlayer model =
    let
        control =
            case model.currentState.controllingPlayer of
                Sako.White ->
                    model.currentState.whiteControl

                Sako.Black ->
                    model.currentState.blackControl
    in
    case control of
        Unlocked ->
            True

        LockedByYou ->
            True

        LockedByYourFrontendAi ->
            False

        LockedByOther ->
            False


legalActionAt : CurrentMatchState -> Tile -> Maybe Sako.Action
legalActionAt state tile =
    state.legalActions
        |> getActionList
        |> List.filter (\action -> Sako.actionTile action == Just tile)
        -- There can never be two actions on the same square, so this is safe.
        |> List.head


liftActionAt : CurrentMatchState -> Tile -> Maybe Sako.Action
liftActionAt state tile =
    state.legalActions
        |> getActionList
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


updateMouseDown : Shared.Model -> BoardMousePosition -> Model -> ( Model, Effect Msg )
updateMouseDown shared pos model =
    -- Check if there is a piece we can lift at this position.
    case Maybe.andThen (liftActionAt model.currentState) pos.tile of
        Just action ->
            updateActionInputStep shared
                action
                { model
                    | dragState = Just { start = pos, current = pos }
                }

        Nothing ->
            updateTryRegrabLiftedPiece pos model


{-| Checks if there is already a lifted piece at the given position and allows
us to take hold of it again.
-}
updateTryRegrabLiftedPiece : BoardMousePosition -> Model -> ( Model, Effect Msg )
updateTryRegrabLiftedPiece pos model =
    let
        liftedPieces =
            Sako.liftedAtTile model.board
    in
    if liftedPieces == pos.tile && pos.tile /= Nothing then
        ( { model
            | dragState = Just { start = pos, current = pos }
            , timeline =
                Animation.interrupt
                    (renderPlayViewDragging { start = pos, current = pos } model)
                    model.timeline
          }
        , Effect.none
        )

    else
        ( model, Effect.none )


{-| Handles a mouse up on the board. We care about the following actions:

1.  When the board is settled (no lifted pieces), a click on a legal action performs it.
2.  When a piece is lifted but not chained, a non-legal action rolls back the move.

Future improvements:

  - When clicking on a explicitly forbidden move, roll back the move.
  - When a piece is lifted, clicking another piece that may lift, should lift the new piece.
    Right now, it only puts down the lifted piece and you need to click a second time.
  - When a piece is lifted, clicking on the same piece should put it down.

-}
updateMouseUp : Shared.Model -> BoardMousePosition -> Model -> ( Model, Effect Msg )
updateMouseUp shared pos model =
    case Maybe.andThen (legalActionAt model.currentState) pos.tile of
        -- Check if the position is an allowed action.
        Just action ->
            updateActionInputStep shared action { model | dragState = Nothing }

        Nothing ->
            ( { model | dragState = Nothing }
                |> softAnimateToCurrentBoard
            , if isQuickRollbackSituation pos model then
                sendRollback model |> Effect.fromCmd

              else
                Effect.none
            )


sendRollback : Model -> Cmd msg
sendRollback model =
    Api.Websocket.send (Api.Websocket.Rollback model.gameKey)


{-| Determines if the current board state allows a quick rollback. This happens
in all situations where the player would not loose much process. (Chains mostly.)
-}
isQuickRollbackSituation : BoardMousePosition -> Model -> Bool
isQuickRollbackSituation pos model =
    not (Sako.isChaining model.board)
        && not (Sako.isPromoting model.board)
        && pos.tile
        /= Sako.liftedAtTile model.board


updateMouseMove : BoardMousePosition -> Model -> ( Model, Effect Msg )
updateMouseMove mousePosition model =
    case model.dragState of
        Just dragState ->
            updateMouseMoveDragging
                { dragState
                    | current = mousePosition
                }
                model

        Nothing ->
            ( model, Effect.none )


updateMouseMoveDragging :
    { start : BoardMousePosition
    , current : BoardMousePosition
    }
    -> Model
    -> ( Model, Effect Msg )
updateMouseMoveDragging dragState model =
    ( { model
        | dragState =
            Just dragState
        , timeline =
            Animation.interrupt
                (renderPlayViewDragging dragState model)
                model.timeline
      }
    , Effect.none
    )


renderPlayViewDragging :
    { start : BoardMousePosition
    , current : BoardMousePosition
    }
    -> Model
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
        , rotation = model.rotation
        }
        model.board


{-| Add the given action to the list of all actions taken and sends it to the
server for confirmation. Will also trigger an animation.
-}
updateActionInputStep : Shared.Model -> Sako.Action -> Model -> ( Model, Effect Msg )
updateActionInputStep shared action model =
    let
        newBoard =
            Sako.doAction action model.board
                |> Maybe.withDefault model.board

        newState =
            addActionToCurrentMatchState action model.currentState
    in
    ( { model | board = newBoard, currentState = newState }
        |> softAnimateToCurrentBoard
    , Effect.batch
        [ Api.Websocket.DoAction
            { key = model.gameKey
            , action = action
            }
            |> Api.Websocket.send
            |> Effect.fromCmd
        , if shared.playSounds then
            case action of
                Sako.Place _ ->
                    Api.Ports.playSound () |> Effect.fromCmd

                Sako.Lift _ ->
                    Effect.none

                Sako.Promote _ ->
                    Effect.none

          else
            Effect.none
        , { action_history = newState.actionHistory, setup = model.currentState.setupOptions }
            |> Api.EncoderGen.determineLegalActions
            |> Api.MessageGen.determineLegalActions
            |> Effect.fromCmd
        ]
    )


{-| Ensure that the update we got actually belongs to the game we are interested
in.
-}
updateCurrentMatchStateIfKeyCorrect : Shared.Model -> CurrentMatchState -> Model -> ( Model, Effect Msg )
updateCurrentMatchStateIfKeyCorrect shared data model =
    if data.key == model.gameKey then
        let
            ( m2, e ) =
                updateCurrentMatchState data model

            ( m3, e2 ) =
                triggerAiMoveIfNecessary shared m2
        in
        ( m3, Effect.batch [ e, e2 ] )

    else
        ( model, Effect.none )


{-| Checks if we have "Ai Control" of the current player. If so checks if the AI
is already running or generates a move.
-}
triggerAiMoveIfNecessary : Shared.Model -> Model -> ( Model, Effect Msg )
triggerAiMoveIfNecessary shared model =
    let
        sideControl =
            case model.currentState.controllingPlayer of
                Sako.White ->
                    model.currentState.whiteControl

                Sako.Black ->
                    model.currentState.blackControl

        isAiControl =
            sideControl == LockedByYourFrontendAi

        isAiReady =
            shared.aiState == AiReadyForRequest

        -- This is a proxy for "controlling_player correct" which means the data model is a bit wonky..
        areLegalActionsDetermined =
            model.currentState.legalActions /= ActionsNotLoaded
    in
    if shared.aiState == Ai.NotInitialized Ai.NotStarted && isThereAnActivePlayerControlledAi model then
        ( model, Effect.fromShared Shared.StartUpAi )

    else if isAiControl && isAiReady && areLegalActionsDetermined then
        determineAiMove model

    else
        ( model, Effect.none )


determineAiMove : Model -> ( Model, Effect Msg )
determineAiMove model =
    ( model
    , Effect.fromShared
        (Shared.DetermineAiMove
            { action_history = model.currentState.actionHistory, setup = model.currentState.setupOptions }
        )
    )


softAnimateToCurrentBoard : Model -> Model
softAnimateToCurrentBoard model =
    { model
        | timeline =
            Animation.queue
                ( Animation.milliseconds 200, PositionView.renderStatic model.rotation model.board )
                model.timeline
    }


updateCurrentMatchState : CurrentMatchState -> Model -> ( Model, Effect Msg )
updateCurrentMatchState newState model =
    let
        determineActionsEffect =
            { action_history = newState.actionHistory, setup = newState.setupOptions }
                |> Api.EncoderGen.determineLegalActions
                |> Api.MessageGen.determineLegalActions
                |> Effect.fromCmd

        modelWithRetainedActions =
            { model
                | currentState =
                    { newState
                        | legalActions = model.currentState.legalActions
                        , actionHistory = model.currentState.actionHistory
                        , canRollback = model.currentState.canRollback
                        , controllingPlayer = model.currentState.controllingPlayer
                    }
            }

        setupOptionsChanged =
            model.currentState.setupOptions /= newState.setupOptions
    in
    if newState.isRollback || setupOptionsChanged then
        let
            startingPosition =
                Fen.parseFen newState.setupOptions.startingFen
                    |> Maybe.withDefault Sako.emptyPosition

            newBoard =
                Sako.doActionsList newState.actionHistory startingPosition
                    |> Maybe.withDefault Sako.emptyPosition
        in
        ( { model | currentState = newState, board = newBoard }
            |> softAnimateToCurrentBoard
        , determineActionsEffect
        )

    else
        case matchStatesDiff model.currentState newState of
            -- No action change, but maybe a status change, like a timeout or draw.
            Custom.List.ListsAreEqual ->
                if List.isEmpty newState.actionHistory then
                    -- On empty lists (new games) this triggers initial action determination.
                    ( modelWithRetainedActions, determineActionsEffect )

                else
                    ( modelWithRetainedActions, Effect.none )

            Custom.List.NewExtendsOld diffActions ->
                let
                    newBoard =
                        Sako.doActionsList diffActions model.board
                            |> Maybe.withDefault model.board
                in
                ( { model | currentState = newState, board = newBoard }
                    |> softAnimateToCurrentBoard
                , determineActionsEffect
                )

            Custom.List.ListsDontExtendEachOther ->
                let
                    startingPosition =
                        Fen.parseFen newState.setupOptions.startingFen
                            |> Maybe.withDefault Sako.emptyPosition

                    newBoard =
                        Sako.doActionsList newState.actionHistory startingPosition
                            |> Maybe.withDefault Sako.emptyPosition
                in
                ( { model | currentState = newState, board = newBoard }
                    |> softAnimateToCurrentBoard
                , determineActionsEffect
                )

            -- The old list extends the new list, when the client moves faster than the
            -- server can acknowledge. We still should take over most of the new state
            -- and just add the missing actions + legal actions back. But no animation.
            Custom.List.OldExtendsNew _ ->
                ( modelWithRetainedActions, Effect.none )


{-| Given an old and a new match state, this returns the actions that need to
be taken to transform the old state into the new state. Returns Nothing if the
new state does not extend the old state.
-}
matchStatesDiff : CurrentMatchState -> CurrentMatchState -> Custom.List.ListDiff Sako.Action
matchStatesDiff old new =
    Custom.List.diff old.actionHistory new.actionHistory


setRotation : BoardRotation -> Model -> Model
setRotation rotation model =
    { model | rotation = rotation }
        |> softAnimateToCurrentBoard


updateWebsocket : Shared.Model -> Api.Websocket.ServerMessage -> Model -> ( Model, Effect Msg )
updateWebsocket shared serverMessage model =
    case serverMessage of
        Api.Websocket.TechnicalError errorMessage ->
            ( model, Api.Ports.logToConsole errorMessage |> Effect.fromCmd )

        Api.Websocket.NewMatchState data ->
            updateCurrentMatchStateIfKeyCorrect shared data model

        Api.Websocket.TimeDriftRespose data ->
            ( model
            , Task.perform
                (\now ->
                    TimeDriftResponseTriple
                        { send = data.send
                        , bounced = data.bounced
                        , back = now
                        }
                )
                Time.now
                |> Effect.fromCmd
            )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Animation.subscription model.timeline AnimationTick
        , Api.Websocket.listen WebsocketMsg WebsocketErrorMsg
        , Api.Websocket.listenToStatus WebsocketStatusChange
        , Custom.Events.onKeyUp keybindings
        , Browser.Events.onResize (\_ y -> SetWindowHeight y)
        , Api.Ports.scrollTrigger (\_ -> FetchHeaderSize)
        , Api.MessageGen.subscribePort PortError
            Api.MessageGen.legalActionsDetermined
            Api.DecoderGen.legalActionsDetermined
            LegalActionsResponse
        , Api.MessageGen.subscribePort PortError
            Api.MessageGen.aiMoveDetermined
            Api.DecoderGen.aiMoveDetermined
            AiMoveResponse
        , Ai.aiStateSub PortError (\_ -> AiStateUpdated)
        ]


{-| The central pace to register all page wide shortcuts.
-}
keybindings : List (KeyBinding Msg)
keybindings =
    [ forKey "1" |> fireMsg (SetInputMode Nothing)
    , forKey "2" |> fireMsg (SetInputMode (Just CastingDeco.InputTiles))
    , forKey "3" |> fireMsg (SetInputMode (Just (CastingDeco.InputArrows Arrow.defaultArrowColor)))
    , forKey "4" |> fireMsg (SetInputMode (Just (CastingDeco.InputArrows "rgb(200, 0, 255, 0.5)")))
    , forKey "5" |> fireMsg (SetInputMode (Just (CastingDeco.InputArrows "rgb(0, 0, 0, 0.5)")))
    , forKey "6" |> fireMsg (SetInputMode (Just (CastingDeco.InputArrows "rgb(255, 255, 255, 0.7)")))
    , forKey " " |> fireMsg ClearDecoComplete
    , forKey "0" |> fireMsg ClearDecoComplete
    ]



-- VIEW


view : Shared.Model -> Model -> View Msg
view shared model =
    { title = T.gameTitle
    , element =
        Header.wrapWithHeaderV2 shared
            ToShared
            { isRouteHighlighted = \_ -> False
            , isWithBackground = False
            }
            (playUi shared model)
    }


playUi : Shared.Model -> Model -> Element Msg
playUi shared model =
    case Reactive.orientation shared.windowSize of
        Reactive.Landscape ->
            Element.column [ width fill, height fill ]
                [ playUiLandscape shared model
                , Element.el
                    [ height
                        (px
                            (max model.visibleHeaderSize
                                (model.windowHeight - model.visibleHeaderSize - model.elementHeight)
                            )
                        )
                    ]
                    Element.none
                ]

        Reactive.Portrait ->
            playUiPortrait shared model


playUiLandscape : Shared.Model -> Model -> Element Msg
playUiLandscape shared model =
    el [ centerX, height fill, width (Element.maximum 1120 fill) ]
        (Element.row
            [ width fill, height fill, paddingXY 10 0, spacing 10 ]
            [ playPositionView shared model
            , sidebarLandscape shared model
            ]
        )


playUiPortrait : Shared.Model -> Model -> Element Msg
playUiPortrait shared model =
    Element.column
        [ width fill, height fill ]
        [ playPositionView shared model
        , sidebarPortrait shared model
        ]


playPositionView : Shared.Model -> Model -> Element Msg
playPositionView shared model =
    Element.el
        [ width fill
        , height
            (Element.maximum
                (min
                    (model.windowHeight - model.visibleHeaderSize)
                    (round Svg.TimerGraphic.playTimerReplaceViewport.height)
                )
                fill
            )
        ]
        (PositionView.viewTimeline
            { colorScheme = Colors.configToOptions shared.colorConfig
            , nodeId = Just sakoEditorId
            , decoration = playDecoration model
            , dragPieceData = []
            , mouseDown = Just MouseDown
            , mouseUp = Just MouseUp
            , mouseMove = Just MouseMove
            , rightClick = Just (\_ -> Rollback)
            , additionalSvg = additionalSvg shared model
            , replaceViewport = Just Svg.TimerGraphic.playTimerReplaceViewport
            }
            model.timeline
        )


isAiPlayer : Maybe PublicUserData -> Bool
isAiPlayer data =
    data |> Maybe.andThen .ai |> Maybe.isJust


canPotentiallyControlAi : ControlLevel -> Bool
canPotentiallyControlAi level =
    case level of
        LockedByOther ->
            False

        _ ->
            True


{-| Checks if either side is an AI where the current browser may need to generate moves. Used to trigger AI init.
-}
isThereAnActivePlayerControlledAi : Model -> Bool
isThereAnActivePlayerControlledAi model =
    if model.currentState.gameState /= Sako.Running then
        False

    else if isAiPlayer model.currentState.whitePlayer && canPotentiallyControlAi model.currentState.whiteControl then
        True

    else if isAiPlayer model.currentState.blackPlayer && canPotentiallyControlAi model.currentState.blackControl then
        True

    else
        False


{-| If there is reason to load to AI, then this shows the loading progress in the sidebar. Hidden when loaded.
-}
aiLoadingInformation : Shared.Model -> Model -> Element msg
aiLoadingInformation shared model =
    if isThereAnActivePlayerControlledAi model then
        case shared.aiState of
            NotInitialized progress ->
                Ai.aiProgressLabel progress

            WaitingForAiAnswer startTime ->
                if Time.posixToMillis shared.now - Time.posixToMillis startTime > 3000 then
                    Ai.aiSlowdownLabel shared.now startTime

                else
                    Element.none

            _ ->
                Element.none

    else
        Element.none


sakoEditorId : String
sakoEditorId =
    "sako-editor"


playDecoration : Model -> List PositionView.BoardDecoration
playDecoration play =
    (play.currentState.legalActions
        |> getActionList
        |> List.filterMap actionDecoration
    )
        ++ playViewHighlight play
        ++ CastingDeco.toDecoration PositionView.castingDecoMappers play.castingDeco
        ++ (PositionView.pastMovementIndicatorList play.board play.currentState.actionHistory
                |> List.map PositionView.PastMovementIndicator
           )


actionDecoration : Sako.Action -> Maybe PositionView.BoardDecoration
actionDecoration action =
    case action of
        Sako.Place tile ->
            Just (PositionView.PlaceTarget tile)

        _ ->
            Nothing


{-| Decides what kind of highlight should be shown when rendering the play view.
-}
playViewHighlight : Model -> List BoardDecoration
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


additionalSvg : Shared.Model -> Model -> Maybe (Svg a)
additionalSvg shared model =
    (Svg.TimerGraphic.playTimerSvg shared.now model
        :: List.map Just
            (Svg.PlayerLabel.both
                { rotation = model.rotation
                , whitePlayer =
                    model.currentState.whitePlayer
                        |> Maybe.withDefault (Svg.PlayerLabel.anonymousPlayerDataFromControl model.currentState.whiteControl)
                , blackPlayer =
                    model.currentState.blackPlayer
                        |> Maybe.withDefault (Svg.PlayerLabel.anonymousPlayerDataFromControl model.currentState.blackControl)
                , victoryState = model.currentState.gameState
                , isWithTimer = Maybe.isJust model.currentState.timer
                , currentPlayer = Just model.currentState.controllingPlayer
                }
            )
    )
        |> List.filterMap identity
        |> Svg.g []
        |> Just


sidebarLandscape : Shared.Model -> Model -> Element Msg
sidebarLandscape shared model =
    Element.column [ spacing 5, width (px 250), height fill, paddingXY 0 40 ]
        [ Components.gameCodeLabel
            (CopyToClipboard (Url.toString model.gameUrl))
            model.gameKey
        , rollbackButton model
        , aiLoadingInformation shared model
        , showIf (canPromote model.currentState.legalActions) promotionButtonGrid
        , maybeVictoryStateInfo model.currentState.gameState
        , maybeReplayLink model
        , Element.el [ padding 10 ] Element.none
        , CastingDeco.configView castingDecoMessages model.inputMode model.castingDeco
        , Element.el [ padding 10 ] Element.none
        , Element.text T.gamePlayAs
        , rotationButtons model.rotation
        , tempAiMoveButton shared
        , Element.el [ padding 10 ] Element.none
        ]


sidebarPortrait : Shared.Model -> Model -> Element Msg
sidebarPortrait shared model =
    Element.column [ spacing 5, width fill, height fill, paddingXY 5 0 ]
        [ showIf (canPromote model.currentState.legalActions) promotionButtonRow
        , Components.gameCodeLabel
            (CopyToClipboard (Url.toString model.gameUrl))
            model.gameKey
        , rollbackButton model
        , maybeVictoryStateInfo model.currentState.gameState
        , maybeReplayLink model
        , Element.el [ padding 10 ] Element.none
        , CastingDeco.configView castingDecoMessages model.inputMode model.castingDeco
        , Element.el [ padding 10 ] Element.none
        , Element.text T.gamePlayAs
        , rotationButtons model.rotation
        , tempAiMoveButton shared
        , Element.el [ padding 10 ] Element.none
        ]


{-| This button allows you to restart your move. This is helpful when your chain
doesn't quite work as expected and it is absolutely required if you get stuck in
a dead end. This means there are three states to the button:

    * The button is disabled. Please lift a piece.
    * The button is enabled and you can click it.
    * The button is enabled and you should click it, because you are stuck.

If we don't know about the legal actions because we are waiting for a server
response, then the button is disabled.

If the game is over, then the button is also disabled.

-}
rollbackButton : Model -> Element Msg
rollbackButton model =
    let
        data =
            case getRollbackButtonState model of
                RollbackButtonDisabled ->
                    { bg = Element.rgb255 220 220 220, hbg = Element.rgb255 220 220 220, fg = Element.rgb255 100 100 100, event = Nothing }

                RollbackButtonSuggested ->
                    { bg = Element.rgb255 51 191 255, hbg = Element.rgb255 102 206 255, fg = Element.rgb255 0 0 0, event = Just Rollback }

                RollbackButtonEnabled ->
                    { bg = Element.rgb255 220 220 220, hbg = Element.rgb255 200 200 200, fg = Element.rgb255 0 0 0, event = Just Rollback }
    in
    Input.button
        [ Background.color data.bg
        , Element.mouseOver [ Background.color data.hbg ]
        , width fill
        , Border.rounded 5
        , Font.color data.fg
        ]
        { onPress = data.event
        , label =
            Element.el [ height fill, centerX, padding 15 ]
                (Element.text T.gameRestartMove)
        }


type RollbackButtonState
    = RollbackButtonDisabled
    | RollbackButtonEnabled
    | RollbackButtonSuggested


getRollbackButtonState : Model -> RollbackButtonState
getRollbackButtonState model =
    case model.currentState.legalActions of
        Api.Decoders.ActionsNotLoaded ->
            RollbackButtonDisabled

        Api.Decoders.ActionsLoaded actions ->
            if not model.currentState.canRollback then
                RollbackButtonDisabled

            else if List.isEmpty actions then
                RollbackButtonSuggested

            else
                RollbackButtonEnabled


{-| A button that is implemented via a vertical column.
-}
bigRoundedButton : Element.Color -> Maybe msg -> List (Element msg) -> Element msg
bigRoundedButton color event content =
    Input.button [ Background.color color, width fill, height fill, Border.rounded 5 ]
        { onPress = event
        , label = Element.column [ height fill, centerX, padding 15, spacing 10 ] content
        }


castingDecoMessages : CastingDeco.Messages Msg
castingDecoMessages =
    { setInputMode = SetInputMode
    , clearTiles = ClearDecoTiles
    , clearArrows = ClearDecoArrows
    }


canPromote : Api.Decoders.LegalActions -> Bool
canPromote actions =
    actions
        |> getActionList
        |> List.any
            (\a ->
                case a of
                    Sako.Promote _ ->
                        True

                    _ ->
                        False
            )


promotionButtonGrid : Element Msg
promotionButtonGrid =
    Element.column [ width fill, spacing 5 ]
        [ Element.row [ width fill, spacing 5 ]
            [ promotionButton Sako.Queen Solid.chessQueen T.queen
            , promotionButton Sako.Knight Solid.chessKnight T.knight
            ]
        , Element.row [ width fill, spacing 5 ]
            [ promotionButton Sako.Rook Solid.chessRook T.rook
            , promotionButton Sako.Bishop Solid.chessBishop T.bishop
            ]
        ]


promotionButtonRow : Element Msg
promotionButtonRow =
    Element.column [ width fill, spacing 5 ]
        [ Element.row [ width fill, spacing 5 ]
            [ promotionButton Sako.Queen Solid.chessQueen T.queen
            , promotionButton Sako.Knight Solid.chessKnight T.knight
            , promotionButton Sako.Rook Solid.chessRook T.rook
            , promotionButton Sako.Bishop Solid.chessBishop T.bishop
            ]
        ]


promotionButton : Sako.Type -> Icon -> String -> Element Msg
promotionButton pieceType pieceIcon caption =
    bigRoundedButton (Element.rgb255 200 240 200)
        (Just (Promote pieceType))
        [ icon [ centerX ] pieceIcon
        , Element.el [ centerX ] (Element.text caption)
        ]


maybeVictoryStateInfo : Sako.VictoryState -> Element msg
maybeVictoryStateInfo victoryState =
    case victoryState of
        Sako.Running ->
            Element.none

        Sako.PacoVictory Sako.White ->
            bigRoundedVictoryStateLabel (Element.rgb255 255 215 0)
                [ Element.el [ Font.size 30, centerX ] (Element.text T.gamePacoWhite)
                ]

        Sako.PacoVictory Sako.Black ->
            bigRoundedVictoryStateLabel (Element.rgb255 255 215 0)
                [ Element.el [ Font.size 30, centerX ] (Element.text T.gamePacoBlack)
                ]

        Sako.TimeoutVictory Sako.White ->
            bigRoundedVictoryStateLabel (Element.rgb255 255 215 0)
                [ Element.el [ Font.size 30, centerX ] (Element.text T.gamePacoWhite)
                , Element.el [ Font.size 20, centerX ] (Element.text T.gameTimeout)
                ]

        Sako.TimeoutVictory Sako.Black ->
            bigRoundedVictoryStateLabel (Element.rgb255 255 215 0)
                [ Element.el [ Font.size 30, centerX ] (Element.text T.gamePacoBlack)
                , Element.el [ Font.size 20, centerX ] (Element.text T.gameTimeout)
                ]

        Sako.NoProgressDraw ->
            bigRoundedVictoryStateLabel (Element.rgb255 255 215 0)
                [ Element.el [ Font.size 30, centerX ] (Element.text T.gameDraw)
                ]

        Sako.RepetitionDraw ->
            bigRoundedVictoryStateLabel (Element.rgb255 255 215 0)
                [ Element.el [ Font.size 30, centerX ] (Element.text T.gameDraw)
                ]


{-| Links to the replay, but only after the game is finished.
-}
maybeReplayLink : Model -> Element Msg
maybeReplayLink model =
    case model.currentState.gameState of
        Sako.Running ->
            Element.none

        _ ->
            colorButton [ width fill ]
                { background = Element.rgb255 51 191 255
                , backgroundHover = Element.rgb255 102 206 255
                , onPress = Just (ToShared (Shared.NavigateTo (Route.toHref (Route.Replay__Id_ { id = model.gameKey }))))
                , buttonIcon = icon [ centerX ] Solid.film
                , caption = T.gameWatchReplay
                }


{-| Label that is used for the Victory status.
-}
bigRoundedVictoryStateLabel : Element.Color -> List (Element msg) -> Element msg
bigRoundedVictoryStateLabel color content =
    Element.el [ Background.color color, width fill, Border.rounded 5 ]
        (Element.column [ height fill, centerX, padding 15, spacing 5 ]
            content
        )


rotationButtons : BoardRotation -> Element Msg
rotationButtons rotation =
    Element.row [ spacing 5 ]
        [ rotationButton WhiteBottom rotation T.gameWhite
        , rotationButton BlackBottom rotation T.gameBlack
        ]


rotationButton : BoardRotation -> BoardRotation -> String -> Element Msg
rotationButton rotation currentRotation label =
    btn label
        |> withMsgIf (rotation /= currentRotation) (SetRotation rotation)
        |> isSelectedIf (rotation == currentRotation)
        |> viewButton



--------------------------------------------------------------------------------
-- AI Integration --------------------------------------------------------------
--------------------------------------------------------------------------------


tempAiMoveButton : Shared.Model -> Element Msg
tempAiMoveButton shared =
    if Shared.isRolf shared then
        Components.colorButton []
            { background = Element.rgb255 51 191 255
            , backgroundHover = Element.rgb255 102 206 255
            , onPress = Just DetermineAiMove
            , buttonIcon = icon [ centerX ] Solid.dice
            , caption = "Generate AI Move"
            }

    else
        Element.none
