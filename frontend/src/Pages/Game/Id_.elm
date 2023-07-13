module Pages.Game.Id_ exposing (Model, Msg, Params, page)

import Animation exposing (Timeline)
import Api.Decoders exposing (CurrentMatchState, getActionList)
import Api.Ports as Ports
import Api.Websocket
import Browser.Dom
import Browser.Events
import CastingDeco
import Colors
import Components exposing (btn, isSelectedIf, viewButton, withMsgIf)
import Custom.Element exposing (icon)
import Custom.Events exposing (BoardMousePosition, KeyBinding, fireMsg, forKey)
import Dict exposing (Dict)
import Duration
import Effect exposing (Effect)
import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import FontAwesome.Solid as Solid
import Gen.Route as Route
import Header
import Json.Decode as Decode
import List.Extra as List
import Maybe.Extra as Maybe
import Page
import PositionView exposing (BoardDecoration(..), DragState, DraggingPieces(..), Highlight(..), OpaqueRenderData)
import Process
import Reactive exposing (DeviceOrientation(..))
import Request
import Sako exposing (Tile(..))
import SaveState exposing (SaveState(..))
import Shared
import Svg exposing (Svg)
import Svg.Attributes as SvgA
import Svg.Custom as Svg exposing (BoardRotation(..))
import Task
import Time exposing (Posix)
import Timer
import Translations as T
import Url
import Url.Parser exposing (query)
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared { params, query, url } =
    Page.advanced
        { init = init params query url
        , update = update
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
    , whiteName : String
    , blackName : String
    , gameUrl : Url.Url
    , colorSettings : Colors.ColorOptions
    , timeDriftMillis : Float
    , windowHeight : Int
    , visibleHeaderSize : Int
    , elementHeight : Int
    }


init : Params -> Dict String String -> Url.Url -> ( Model, Effect Msg )
init params query url =
    ( { board = Sako.initialPosition
      , gameKey = params.id
      , currentState =
            { key = ""
            , actionHistory = []
            , legalActions = Api.Decoders.ActionsNotLoaded
            , controllingPlayer = Sako.White
            , timer = Nothing
            , gameState = Sako.Running
            }
      , timeline = Animation.init (PositionView.renderStatic WhiteBottom Sako.initialPosition)
      , focus = Nothing
      , dragState = Nothing
      , castingDeco = CastingDeco.initModel
      , inputMode = Nothing
      , rotation = WhiteBottom
      , whiteName = ""
      , blackName = ""
      , gameUrl = url
      , colorSettings = determineColorSettingsFromQuery query
      , timeDriftMillis = 0
      , windowHeight = 500
      , visibleHeaderSize = 0
      , elementHeight = 500
      }
    , Cmd.batch
        [ Api.Websocket.send (Api.Websocket.SubscribeToMatch params.id)
        , -- This is not really nice, but we want to give the websocket time to
          -- connect. This is why we wait five seconds.
          -- May be better to move this into typescript.
          Process.sleep 5000
            |> Task.andThen (\() -> Time.now)
            |> Task.perform (\now -> TimeDriftRequestTrigger { send = now })
        , Browser.Dom.getViewport
            |> Task.perform (\data -> SetWindowHeight (round data.viewport.height))
        , fetchHeaderSize
        ]
        |> Effect.fromCmd
    )


determineColorSettingsFromQuery : Dict String String -> Colors.ColorOptions
determineColorSettingsFromQuery dict =
    Dict.get "colors" dict
        |> Maybe.map Colors.getOptionsByName
        |> Maybe.withDefault (Colors.configToOptions Colors.defaultBoardColors)



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
    | SetWhiteName String
    | SetBlackName String
    | CopyToClipboard String
    | WebsocketStatusChange Api.Websocket.WebsocketConnectionState
    | ToShared Shared.Msg
    | TimeDriftRequestTrigger { send : Posix }
    | TimeDriftResponseTriple { send : Posix, bounced : Posix, back : Posix }
    | SetWindowHeight Int
    | FetchHeaderSize
    | SetVisibleHeaderSize { header : Int, elementHeight : Int }


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        Promote pieceType ->
            updateActionInputStep (Sako.Promote pieceType) model

        AnimationTick now ->
            ( { model | timeline = Animation.tick now model.timeline }, Effect.none )

        Rollback ->
            ( model
            , Api.Websocket.send (Api.Websocket.Rollback model.gameKey) |> Effect.fromCmd
            )

        MouseDown pos ->
            case model.inputMode of
                Nothing ->
                    updateMouseDown pos model

                Just mode ->
                    ( { model | castingDeco = CastingDeco.mouseDown mode pos model.castingDeco }, Effect.none )

        MouseUp pos ->
            case model.inputMode of
                Nothing ->
                    updateMouseUp pos model

                Just mode ->
                    ( { model | castingDeco = CastingDeco.mouseUp mode pos model.castingDeco }, Effect.none )

        MouseMove pos ->
            case model.inputMode of
                Nothing ->
                    updateMouseMove pos model

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
            updateWebsocket serverMessage model

        WebsocketErrorMsg error ->
            ( model, Ports.logToConsole (Decode.errorToString error) |> Effect.fromCmd )

        SetWhiteName name ->
            ( { model | whiteName = name }, Effect.none )

        SetBlackName name ->
            ( { model | blackName = name }, Effect.none )

        CopyToClipboard text ->
            ( model, Ports.copy text |> Effect.fromCmd )

        WebsocketStatusChange status ->
            ( model
            , case status of
                Api.Websocket.WebsocketConnected ->
                    Api.Websocket.send (Api.Websocket.SubscribeToMatch model.gameKey)
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
            , Ports.logToConsole
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
    }


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


updateMouseDown : BoardMousePosition -> Model -> ( Model, Effect Msg )
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


updateMouseUp : BoardMousePosition -> Model -> ( Model, Effect Msg )
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
                        ( Animation.milliseconds 200, PositionView.renderStatic model.rotation model.board )
                        model.timeline
              }
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
updateActionInputStep : Sako.Action -> Model -> ( Model, Effect Msg )
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
                ( Animation.milliseconds 200, PositionView.renderStatic model.rotation newBoard )
                model.timeline
      }
    , Effect.batch
        [ Api.Websocket.DoAction
            { key = model.gameKey
            , action = action
            }
            |> Api.Websocket.send
            |> Effect.fromCmd
        , case action of
            Sako.Place _ ->
                Ports.playSound () |> Effect.fromCmd

            Sako.Lift _ ->
                Effect.none

            Sako.Promote _ ->
                Effect.none
        ]
    )


{-| Ensure that the update we got actually belongs to the game we are interested
in.
-}
updateCurrentMatchStateIfKeyCorrect : CurrentMatchState -> Model -> ( Model, Effect Msg )
updateCurrentMatchStateIfKeyCorrect data model =
    if data.key == model.currentState.key then
        updateCurrentMatchState data model

    else
        ( model, Effect.none )


updateCurrentMatchState : CurrentMatchState -> Model -> ( Model, Effect Msg )
updateCurrentMatchState data model =
    let
        newBoard =
            case matchStatesDiff model.currentState data of
                Just diffActions ->
                    Sako.doActionsList diffActions model.board
                        |> Maybe.withDefault model.board

                Nothing ->
                    Sako.doActionsList data.actionHistory Sako.initialPosition
                        |> Maybe.withDefault Sako.emptyPosition

        newState =
            data
    in
    ( { model
        | currentState = newState
        , board = newBoard
        , timeline =
            Animation.queue
                ( Animation.milliseconds 200, PositionView.renderStatic model.rotation newBoard )
                model.timeline
      }
    , Effect.none
    )


updateMatchConnectionSuccess : { key : String, state : CurrentMatchState } -> Model -> ( Model, Effect Msg )
updateMatchConnectionSuccess data model =
    { model | gameKey = data.key }
        |> updateCurrentMatchState data.state


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


setRotation : BoardRotation -> Model -> Model
setRotation rotation model =
    { model
        | rotation = rotation
        , timeline =
            Animation.queue
                ( Animation.milliseconds 200, PositionView.renderStatic rotation model.board )
                model.timeline
    }


updateWebsocket : Api.Websocket.ServerMessage -> Model -> ( Model, Effect Msg )
updateWebsocket serverMessage model =
    case serverMessage of
        Api.Websocket.TechnicalError errorMessage ->
            ( model, Ports.logToConsole errorMessage |> Effect.fromCmd )

        Api.Websocket.NewMatchState data ->
            updateCurrentMatchStateIfKeyCorrect data model

        Api.Websocket.MatchConnectionSuccess data ->
            updateMatchConnectionSuccess data model

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
        , Ports.scrollTrigger (\_ -> FetchHeaderSize)
        ]


{-| The central pace to register all page wide shortcuts.
-}
keybindings : List (KeyBinding Msg)
keybindings =
    [ forKey "1" |> fireMsg (SetInputMode Nothing)
    , forKey "2" |> fireMsg (SetInputMode (Just CastingDeco.InputTiles))
    , forKey "3" |> fireMsg (SetInputMode (Just CastingDeco.InputArrows))
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
            , sidebar model
            ]
        )


playUiPortrait : Shared.Model -> Model -> Element Msg
playUiPortrait shared model =
    Element.column
        [ width fill, height fill ]
        [ playPositionView shared model
        , sidebar model
        ]


playPositionView : Shared.Model -> Model -> Element Msg
playPositionView shared model =
    Element.el
        [ width fill
        , height
            (Element.maximum
                (min
                    (model.windowHeight - model.visibleHeaderSize)
                    (round playTimerReplaceViewport.height)
                )
                fill
            )
        ]
        (PositionView.viewTimeline
            { colorScheme = model.colorSettings
            , nodeId = Just sakoEditorId
            , decoration = playDecoration model
            , dragPieceData = []
            , mouseDown = Just MouseDown
            , mouseUp = Just MouseUp
            , mouseMove = Just MouseMove
            , additionalSvg = additionalSvg shared model
            , replaceViewport = Just playTimerReplaceViewport
            }
            model.timeline
        )


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
    let
        ( whiteY, blackY ) =
            case model.rotation of
                WhiteBottom ->
                    ( 850, -40 )

                BlackBottom ->
                    ( -40, 850 )
    in
    [ playTimerSvg shared.now model
    , playerLabelSvg model.whiteName whiteY
    , playerLabelSvg model.blackName blackY
    ]
        |> List.filterMap identity
        |> Svg.g []
        |> Just


playTimerSvg : Posix -> Model -> Maybe (Svg a)
playTimerSvg now model =
    let
        correctedTime =
            Time.posixToMillis now
                |> toFloat
                |> (\n -> n - model.timeDriftMillis)
                |> round
                |> Time.millisToPosix
    in
    model.currentState.timer
        |> Maybe.map (justPlayTimerSvg correctedTime model)


justPlayTimerSvg : Posix -> Model -> Timer.Timer -> Svg a
justPlayTimerSvg now model timer =
    let
        viewData =
            Timer.render model.currentState.controllingPlayer now timer

        increment =
            Maybe.map (Duration.inSeconds >> round) timer.config.increment
    in
    Svg.g []
        [ timerTagSvg
            { caption = timeLabel viewData.secondsLeftWhite
            , player = Sako.White
            , at = Svg.Coord 0 (timerLabelYPosition model.rotation Sako.White)
            , increment = increment
            }
        , timerTagSvg
            { caption = timeLabel viewData.secondsLeftBlack
            , player = Sako.Black
            , at = Svg.Coord 0 (timerLabelYPosition model.rotation Sako.Black)
            , increment = increment
            }
        ]


{-| Determines the Y position of the on-svg timer label. This is required to
flip the labels when the board is flipped to have Black at the bottom.
-}
timerLabelYPosition : BoardRotation -> Sako.Color -> Int
timerLabelYPosition rotation color =
    case ( rotation, color ) of
        ( WhiteBottom, Sako.White ) ->
            820

        ( WhiteBottom, Sako.Black ) ->
            -70

        ( BlackBottom, Sako.White ) ->
            -70

        ( BlackBottom, Sako.Black ) ->
            820


{-| Creates a little rectangle with a text which can be used to display the
timer for one player. Picks colors automatically based on the player.
-}
timerTagSvg :
    { caption : String
    , player : Sako.Color
    , at : Svg.Coord
    , increment : Maybe Int
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

        fullCaption =
            case data.increment of
                Just seconds ->
                    data.caption ++ " +" ++ String.fromInt seconds

                Nothing ->
                    data.caption
    in
    Svg.g [ Svg.translate data.at ]
        [ Svg.rect [ SvgA.width "250", SvgA.height "50", SvgA.fill backgroundColor ] []
        , timerTextSvg (SvgA.fill textColor) fullCaption
        ]


timerTextSvg : Svg.Attribute msg -> String -> Svg msg
timerTextSvg fill caption =
    Svg.text_
        [ SvgA.style "text-anchor:middle;font-size:50px;pointer-events:none;-moz-user-select: none;-webkit-user-select: none;dominant-baseline:middle"
        , SvgA.x "125"
        , SvgA.y "30"
        , fill
        ]
        [ Svg.text caption ]


playerLabelSvg : String -> Int -> Maybe (Svg a)
playerLabelSvg name yPos =
    if String.isEmpty name then
        Nothing

    else
        Just
            (Svg.text_
                [ SvgA.style "text-anchor:left;font-size:50px;pointer-events:none;-moz-user-select: none;-webkit-user-select: none;dominant-baseline:middle"
                , SvgA.x "300"
                , SvgA.y (String.fromInt yPos)
                , SvgA.fill "#595"
                ]
                [ Svg.text name ]
            )


playTimerReplaceViewport :
    { x : Float
    , y : Float
    , width : Float
    , height : Float
    }
playTimerReplaceViewport =
    { x = -10
    , y = -80
    , width = 820
    , height = 960
    }


sidebar : Model -> Element Msg
sidebar model =
    Element.column [ spacing 5, width (px 250), height fill, paddingXY 0 40 ]
        [ Components.gameCodeLabel
            (CopyToClipboard (Url.toString model.gameUrl))
            model.gameKey
        , rollbackButton model
        , maybePromotionButtons model.currentState.legalActions
        , maybeVictoryStateInfo model.currentState.gameState
        , maybeReplayLink model
        , Element.el [ padding 10 ] Element.none
        , CastingDeco.configView castingDecoMessages model.inputMode model.castingDeco
        , Element.el [ padding 10 ] Element.none
        , Element.text T.gamePlayAs
        , rotationButtons model.rotation
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
            if List.any Sako.isLiftAction actions then
                RollbackButtonDisabled

            else if Sako.isStateOver model.currentState.gameState then
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


maybePromotionButtons : Api.Decoders.LegalActions -> Element Msg
maybePromotionButtons actions =
    let
        canPromote =
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
                (Just (Promote  Sako.Queen))
                [ icon [ centerX ] Solid.chessQueen
                , Element.el [ centerX ] (Element.text T.queen)
                ]
            , bigRoundedButton (Element.rgb255 200 240 200)
                (Just (Promote Sako.Knight))
                [ icon [ centerX ] Solid.chessKnight
                , Element.el [ centerX ] (Element.text T.knight)
                ]
            ]
        , Element.row [ width fill, spacing 5 ]
            [ bigRoundedButton (Element.rgb255 200 240 200)
                (Just (Promote Sako.Rook))
                [ icon [ centerX ] Solid.chessRook
                , Element.el [ centerX ] (Element.text T.rook)
                ]
            , bigRoundedButton (Element.rgb255 200 240 200)
                (Just (Promote Sako.Bishop))
                [ icon [ centerX ] Solid.chessBishop
                , Element.el [ centerX ] (Element.text T.bishop)
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
maybeReplayLink : Model -> Element msg
maybeReplayLink model =
    case model.currentState.gameState of
        Sako.Running ->
            Element.none

        _ ->
            Element.link [ padding 10, Font.underline, Font.color (Element.rgb 0 0 1) ]
                { url = Route.toHref (Route.Replay__Id_ { id = model.gameKey })
                , label = Element.text T.gameWatchReplay
                }


{-| Label that is used for the Victory status.
-}
bigRoundedVictoryStateLabel : Element.Color -> List (Element msg) -> Element msg
bigRoundedVictoryStateLabel color content =
    Element.el [ Background.color color, width fill, Border.rounded 5 ]
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
