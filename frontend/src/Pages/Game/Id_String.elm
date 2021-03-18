module Pages.Game.Id_String exposing (Model, Msg, Params, page)

import Animation exposing (Timeline)
import Api.Ai
import Api.Decoders exposing (CurrentMatchState)
import Api.Ports as Ports
import Api.Websocket
import CastingDeco
import Colors
import Components exposing (btn, isSelectedIf, viewButton, withMsg, withMsgIf, withSmallIcon, withStyle)
import Custom.Element exposing (icon)
import Custom.Events exposing (BoardMousePosition, KeyBinding, fireMsg, forKey)
import Dict exposing (Dict)
import Duration
import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import FontAwesome.Regular as Regular
import FontAwesome.Solid as Solid
import I18n.Strings as I18n exposing (I18nToken(..), Language(..), t)
import Json.Decode as Decode
import List.Extra as List
import Maybe.Extra as Maybe
import PositionView exposing (BoardDecoration(..), DragState, DraggingPieces(..), Highlight(..), OpaqueRenderData)
import Reactive exposing (Device(..))
import Result.Extra as Result
import Sako exposing (Tile(..))
import SaveState exposing (SaveState(..))
import Shared
import Spa.Document exposing (Document)
import Spa.Generated.Route as Route
import Spa.Page as Page exposing (Page)
import Spa.Url exposing (Url)
import Svg exposing (Svg)
import Svg.Attributes as SvgA
import Svg.Custom as Svg exposing (BoardRotation(..))
import Time exposing (Posix)
import Timer
import Url
import Url.Parser exposing (query)


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
    { id : String }


type alias Model =
    { board : Sako.Position
    , subscription : Maybe String
    , currentState : CurrentMatchState
    , windowSize : ( Int, Int )
    , timeline : Timeline OpaqueRenderData
    , focus : Maybe Tile
    , dragState : DragState
    , castingDeco : CastingDeco.Model
    , inputMode : Maybe CastingDeco.InputMode
    , rotation : BoardRotation
    , now : Posix
    , lang : Language
    , whiteName : String
    , blackName : String
    , gameUrl : Url.Url
    , colorSettings : Colors.ColorOptions
    }


init : Shared.Model -> Url Params -> ( Model, Cmd Msg )
init shared { params, query } =
    ( { board = Sako.initialPosition
      , windowSize = shared.windowSize
      , subscription = Just params.id
      , currentState =
            { key = ""
            , actionHistory = []
            , legalActions = []
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
      , now = shared.now
      , lang = shared.language
      , whiteName = ""
      , blackName = ""
      , gameUrl = shared.url
      , colorSettings = determineColorSettingsFromQuery query
      }
    , Api.Websocket.send (Api.Websocket.SubscribeToMatch params.id)
    )


determineColorSettingsFromQuery : Dict String String -> Colors.ColorOptions
determineColorSettingsFromQuery dict =
    Dict.get "colors" dict
        |> Maybe.map Colors.getOptionsByName
        |> Maybe.withDefault (Colors.configToOptions Colors.defaultBoardColors)



-- UPDATE


type Msg
    = ActionInputStep Sako.Action
    | Rollback
    | AnimationTick Posix
    | MouseDown BoardMousePosition
    | MouseUp BoardMousePosition
    | MouseMove BoardMousePosition
    | SetInputMode (Maybe CastingDeco.InputMode)
    | ClearDecoTiles
    | ClearDecoArrows
    | ClearDecoComplete
    | MoveFromAi Sako.Action
    | RequestAiMove
    | AiCrashed
    | SetRotation BoardRotation
    | WebsocketMsg Api.Websocket.ServerMessage
    | WebsocketErrorMsg Decode.Error
    | SetWhiteName String
    | SetBlackName String
    | CopyToClipboard String
    | WebsocketStatusChange Api.Websocket.WebsocketStaus


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ActionInputStep action ->
            updateActionInputStep action model

        AnimationTick now ->
            ( { model | timeline = Animation.tick now model.timeline }, Cmd.none )

        Rollback ->
            ( model
            , Api.Websocket.send (Api.Websocket.Rollback (Maybe.withDefault "" model.subscription))
            )

        MouseDown pos ->
            case model.inputMode of
                Nothing ->
                    updateMouseDown pos model

                Just mode ->
                    ( { model | castingDeco = CastingDeco.mouseDown mode pos model.castingDeco }, Cmd.none )

        MouseUp pos ->
            case model.inputMode of
                Nothing ->
                    updateMouseUp pos model

                Just mode ->
                    ( { model | castingDeco = CastingDeco.mouseUp mode pos model.castingDeco }, Cmd.none )

        MouseMove pos ->
            case model.inputMode of
                Nothing ->
                    updateMouseMove pos model

                Just mode ->
                    ( { model | castingDeco = CastingDeco.mouseMove mode pos model.castingDeco }, Cmd.none )

        SetInputMode inputMode ->
            ( { model | inputMode = inputMode }, Cmd.none )

        ClearDecoTiles ->
            ( { model | castingDeco = CastingDeco.clearTiles model.castingDeco }, Cmd.none )

        ClearDecoArrows ->
            ( { model | castingDeco = CastingDeco.clearArrows model.castingDeco }, Cmd.none )

        ClearDecoComplete ->
            ( { model | castingDeco = CastingDeco.initModel }, Cmd.none )

        MoveFromAi action ->
            updateActionInputStep action model

        RequestAiMove ->
            ( model, Api.Ai.requestMoveFromAi )

        AiCrashed ->
            ( model, Ports.logToConsole "Ai Crashed" )

        SetRotation rotation ->
            ( setRotation rotation model, Cmd.none )

        WebsocketMsg serverMessage ->
            updateWebsocket serverMessage model

        WebsocketErrorMsg error ->
            ( model, Ports.logToConsole (Decode.errorToString error) )

        SetWhiteName name ->
            ( { model | whiteName = name }, Cmd.none )

        SetBlackName name ->
            ( { model | blackName = name }, Cmd.none )

        CopyToClipboard text ->
            ( model, Ports.copy text )

        WebsocketStatusChange status ->
            ( model
            , case status of
                Api.Websocket.WSConnected ->
                    Api.Websocket.send (Api.Websocket.SubscribeToMatch (Maybe.withDefault "" model.subscription))
                        |> Debug.log "Reconnected!"

                _ ->
                    Cmd.none
            )


addActionToCurrentMatchState : Sako.Action -> CurrentMatchState -> CurrentMatchState
addActionToCurrentMatchState action state =
    { state
        | actionHistory = state.actionHistory ++ [ action ]
        , legalActions = []
    }


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
updateMouseDown : BoardMousePosition -> Model -> ( Model, Cmd Msg )
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
updateTryRegrabLiftedPiece : BoardMousePosition -> Model -> ( Model, Cmd Msg )
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
        , Cmd.none
        )

    else
        ( model, Cmd.none )


updateMouseUp : BoardMousePosition -> Model -> ( Model, Cmd Msg )
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
                sendRollback model

              else
                Cmd.none
            )


sendRollback : Model -> Cmd msg
sendRollback model =
    Api.Websocket.send (Api.Websocket.Rollback (Maybe.withDefault "" model.subscription))


{-| Determines if the current board state allows a quick rollback. This happens
in all situations where the player would not loose much process. (Chains mostly.)
-}
isQuickRollbackSituation : BoardMousePosition -> Model -> Bool
isQuickRollbackSituation pos model =
    not (Sako.isChaining model.board)
        && not (Sako.isPromoting model.board)
        && pos.tile
        /= Sako.liftedAtTile model.board


updateMouseMove : BoardMousePosition -> Model -> ( Model, Cmd Msg )
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
    -> Model
    -> ( Model, Cmd Msg )
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
updateActionInputStep : Sako.Action -> Model -> ( Model, Cmd Msg )
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
    , Cmd.batch
        [ Api.Websocket.DoAction
            { key = Maybe.withDefault "" model.subscription
            , action = action
            }
            |> Api.Websocket.send
        , case action of
            Sako.Place _ ->
                Ports.playSound ()

            Sako.Lift _ ->
                Cmd.none

            Sako.Promote _ ->
                Cmd.none
        ]
    )


{-| Ensure that the update we got actually belongs to the game we are interested
in.
-}
updateCurrentMatchStateIfKeyCorrect : CurrentMatchState -> Model -> ( Model, Cmd Msg )
updateCurrentMatchStateIfKeyCorrect data model =
    if data.key == model.currentState.key then
        updateCurrentMatchState data model

    else
        ( model, Cmd.none )


updateCurrentMatchState : CurrentMatchState -> Model -> ( Model, Cmd Msg )
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
    , Cmd.none
    )


updateMatchConnectionSuccess : { key : String, state : CurrentMatchState } -> Model -> ( Model, Cmd Msg )
updateMatchConnectionSuccess data model =
    { model | subscription = Just data.key }
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


updateWebsocket : Api.Websocket.ServerMessage -> Model -> ( Model, Cmd Msg )
updateWebsocket serverMessage model =
    case serverMessage of
        Api.Websocket.TechnicalError errorMessage ->
            ( model, Ports.logToConsole errorMessage )

        Api.Websocket.NewMatchState data ->
            updateCurrentMatchStateIfKeyCorrect data model

        Api.Websocket.MatchConnectionSuccess data ->
            updateMatchConnectionSuccess data model


save : Model -> Shared.Model -> Shared.Model
save _ shared =
    shared


load : Shared.Model -> Model -> ( Model, Cmd Msg )
load shared model =
    ( { model
        | lang = shared.language
        , windowSize = shared.windowSize
        , now = shared.now
      }
    , Cmd.none
    )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Animation.subscription model.timeline AnimationTick
        , Api.Websocket.listen WebsocketMsg WebsocketErrorMsg
        , Api.Websocket.listenToStatus WebsocketStatusChange
        , Api.Ai.subscribeMoveFromAi AiCrashed MoveFromAi
        , Custom.Events.onKeyUp keybindings
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


view : Model -> Document Msg
view model =
    { title = t model.lang i18nTitle
    , body = [ playUi model ]
    }


playUi : Model -> Element Msg
playUi model =
    case Reactive.classify model.windowSize of
        LandscapeDevice ->
            playUiLandscape model

        PortraitDevice ->
            playUiPortrait model


playUiLandscape : Model -> Element Msg
playUiLandscape model =
    Element.row
        [ width fill, height fill, Element.scrollbarY ]
        [ playPositionView model
        , sidebar model
        ]


playUiPortrait : Model -> Element Msg
playUiPortrait model =
    Element.column
        [ width fill, height fill ]
        [ playPositionView model
        , sidebar model
        ]


playPositionView : Model -> Element Msg
playPositionView model =
    Element.el [ width fill, height fill ]
        (PositionView.viewTimeline
            { colorScheme = model.colorSettings
            , nodeId = Just sakoEditorId
            , decoration = playDecoration model
            , dragPieceData = []
            , mouseDown = Just MouseDown
            , mouseUp = Just MouseUp
            , mouseMove = Just MouseMove
            , additionalSvg = additionalSvg model
            , replaceViewport = playTimerReplaceViewport model
            }
            model.timeline
        )


sakoEditorId : String
sakoEditorId =
    "sako-editor"


playDecoration : Model -> List PositionView.BoardDecoration
playDecoration play =
    (play.currentState.legalActions
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


additionalSvg : Model -> Maybe (Svg a)
additionalSvg model =
    let
        ( whiteY, blackY ) =
            case model.rotation of
                WhiteBottom ->
                    ( 850, -40 )

                BlackBottom ->
                    ( -40, 850 )
    in
    [ playTimerSvg model.now model
    , playerLabelSvg model.whiteName whiteY
    , playerLabelSvg model.blackName blackY
    ]
        |> List.filterMap identity
        |> Svg.g []
        |> Just


playTimerSvg : Posix -> Model -> Maybe (Svg a)
playTimerSvg now model =
    model.currentState.timer
        |> Maybe.map (justPlayTimerSvg now model)


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
    Model
    ->
        Maybe
            { x : Float
            , y : Float
            , width : Float
            , height : Float
            }
playTimerReplaceViewport model =
    if Maybe.isNothing model.currentState.timer then
        Nothing

    else
        Just
            { x = -70
            , y = -80
            , width = 900
            , height = 960
            }


sidebar : Model -> Element Msg
sidebar model =
    Element.column [ spacing 5, padding 20, height fill ]
        [ gameCodeLabel model model.subscription
        , bigRoundedButton (Element.rgb255 220 220 220)
            (Just Rollback)
            [ Element.text (t model.lang i18nRestartMove) ]
            |> Element.el [ width fill ]
        , maybePromotionButtons model model.currentState.legalActions
        , maybeVictoryStateInfo model model.currentState.gameState
        , maybeReplayLink model
        , Element.el [ padding 10 ] Element.none
        , CastingDeco.configView model.lang castingDecoMessages model.inputMode model.castingDeco
        , Element.el [ padding 10 ] Element.none
        , Element.text (t model.lang i18nPlayAs)
        , rotationButtons model model.rotation
        , Element.el [ padding 10 ] Element.none
        , playerNamesInput model

        -- , Input.button []
        --     { onPress = Just (PlayMsgWrapper RequestAiMove)
        --     , label = Element.text "Request Ai Move"
        --     }
        ]


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


gameCodeLabel : Model -> Maybe String -> Element Msg
gameCodeLabel model subscription =
    case subscription of
        Just id ->
            Element.column [ width fill, spacing 5 ]
                [ Components.gameIdBadgeBig id
                , Element.row [ width fill, height fill ]
                    [ btn (t model.lang i18nCopyToClipboard)
                        |> withSmallIcon Regular.clipboard
                        |> withMsg (CopyToClipboard (Url.toString model.gameUrl))
                        |> withStyle (width fill)
                        |> viewButton
                    ]
                ]

        Nothing ->
            Element.text (t model.lang i18nNotConnected)


maybePromotionButtons : Model -> List Sako.Action -> Element Msg
maybePromotionButtons model actions =
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
        promotionButtons model

    else
        Element.none


promotionButtons : Model -> Element Msg
promotionButtons model =
    Element.column [ width fill, spacing 5 ]
        [ Element.row [ width fill, spacing 5 ]
            [ bigRoundedButton (Element.rgb255 200 240 200)
                (Just (ActionInputStep (Sako.Promote Sako.Queen)))
                [ icon [ centerX ] Solid.chessQueen
                , Element.el [ centerX ] (Element.text (t model.lang I18n.queen))
                ]
            , bigRoundedButton (Element.rgb255 200 240 200)
                (Just (ActionInputStep (Sako.Promote Sako.Knight)))
                [ icon [ centerX ] Solid.chessKnight
                , Element.el [ centerX ] (Element.text (t model.lang I18n.knight))
                ]
            ]
        , Element.row [ width fill, spacing 5 ]
            [ bigRoundedButton (Element.rgb255 200 240 200)
                (Just (ActionInputStep (Sako.Promote Sako.Rook)))
                [ icon [ centerX ] Solid.chessRook
                , Element.el [ centerX ] (Element.text (t model.lang I18n.rook))
                ]
            , bigRoundedButton (Element.rgb255 200 240 200)
                (Just (ActionInputStep (Sako.Promote Sako.Bishop)))
                [ icon [ centerX ] Solid.chessBishop
                , Element.el [ centerX ] (Element.text (t model.lang I18n.bishop))
                ]
            ]
        ]


maybeVictoryStateInfo : Model -> Sako.VictoryState -> Element msg
maybeVictoryStateInfo model victoryState =
    case victoryState of
        Sako.Running ->
            Element.none

        Sako.PacoVictory Sako.White ->
            bigRoundedVictoryStateLabel (Element.rgb255 255 215 0)
                [ Element.el [ Font.size 30, centerX ] (Element.text (t model.lang i18nPacoWhite))
                ]

        Sako.PacoVictory Sako.Black ->
            bigRoundedVictoryStateLabel (Element.rgb255 255 215 0)
                [ Element.el [ Font.size 30, centerX ] (Element.text (t model.lang i18nPacoBlack))
                ]

        Sako.TimeoutVictory Sako.White ->
            bigRoundedVictoryStateLabel (Element.rgb255 255 215 0)
                [ Element.el [ Font.size 30, centerX ] (Element.text (t model.lang i18nPacoWhite))
                , Element.el [ Font.size 20, centerX ] (Element.text (t model.lang i18nTimeout))
                ]

        Sako.TimeoutVictory Sako.Black ->
            bigRoundedVictoryStateLabel (Element.rgb255 255 215 0)
                [ Element.el [ Font.size 30, centerX ] (Element.text (t model.lang i18nPacoBlack))
                , Element.el [ Font.size 20, centerX ] (Element.text (t model.lang i18nTimeout))
                ]


{-| Links to the replay, but only after the game is finished.
-}
maybeReplayLink : Model -> Element msg
maybeReplayLink model =
    case model.currentState.gameState of
        Sako.Running ->
            Element.none

        _ ->
            model.subscription
                |> Maybe.map
                    (\key ->
                        Element.link [ padding 10, Font.underline, Font.color (Element.rgb 0 0 1) ]
                            { url = Route.toString (Route.Replay__Id_String { id = key })
                            , label = Element.text (t model.lang i18nWatchReplay)
                            }
                    )
                |> Maybe.withDefault Element.none


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


rotationButtons : Model -> BoardRotation -> Element Msg
rotationButtons model rotation =
    Element.row [ spacing 5 ]
        [ rotationButton WhiteBottom rotation (t model.lang i18nWhite)
        , rotationButton BlackBottom rotation (t model.lang i18nBlack)
        ]


rotationButton : BoardRotation -> BoardRotation -> String -> Element Msg
rotationButton rotation currentRotation label =
    btn label
        |> withMsgIf (rotation /= currentRotation) (SetRotation rotation)
        |> isSelectedIf (rotation == currentRotation)
        |> viewButton


playerNamesInput : Model -> Element Msg
playerNamesInput model =
    let
        whitePlayerName =
            Element.text (t model.lang i18nWhitePlayerName)

        blackPlayerName =
            Element.text (t model.lang i18nBlackPlayerName)
    in
    Element.column [ spacing 5 ]
        [ Element.text (t model.lang i18nPlayerNamesForStreaming)
        , Input.text []
            { onChange = SetWhiteName
            , text = model.whiteName
            , placeholder = Just (Input.placeholder [] whitePlayerName)
            , label = Input.labelAbove [] whitePlayerName
            }
        , Input.text []
            { onChange = SetBlackName
            , text = model.blackName
            , placeholder = Just (Input.placeholder [] blackPlayerName)
            , label = Input.labelAbove [] blackPlayerName
            }
        ]



--------------------------------------------------------------------------------
-- I18n Strings ----------------------------------------------------------------
--------------------------------------------------------------------------------


i18nTitle : I18nToken String
i18nTitle =
    I18nToken
        { english = "Play Paco Ŝako - pacoplay.com"
        , dutch = "Speel Paco Ŝako - pacoplay.com"
        , esperanto = "Ludi Paco Ŝako - pacoplay.com"
        }


i18nCopyToClipboard : I18nToken String
i18nCopyToClipboard =
    I18nToken
        { english = "Copy url for a friend"
        , dutch = "Kopieer de url voor een vriend"
        , esperanto = "Kopiu url por amikon"
        }


i18nRestartMove : I18nToken String
i18nRestartMove =
    I18nToken
        { english = "Restart move"
        , dutch = "Herstart verplaatsen"
        , esperanto = "Rekomenci movon"
        }


i18nPlayAs : I18nToken String
i18nPlayAs =
    I18nToken
        { english = "Play as:"
        , dutch = "Speel als:"
        , esperanto = "Ludi kiel:"
        }


i18nNotConnected : I18nToken String
i18nNotConnected =
    I18nToken
        { english = "Not connected"
        , dutch = "Niet verbonden"
        , esperanto = "Ne konektita"
        }


i18nPacoWhite : I18nToken String
i18nPacoWhite =
    I18nToken
        { english = "Paco White"
        , dutch = "Paco Wit"
        , esperanto = "Paco Blanko"
        }


i18nPacoBlack : I18nToken String
i18nPacoBlack =
    I18nToken
        { english = "Paco Black"
        , dutch = "Paco Zwart"
        , esperanto = "Paco Nigro"
        }


i18nTimeout : I18nToken String
i18nTimeout =
    I18nToken
        { english = "(Timeout)"
        , dutch = "(Time-out)"
        , esperanto = "(Tempolimo)"
        }


i18nWatchReplay : I18nToken String
i18nWatchReplay =
    I18nToken
        { english = "Watch Replay"
        , dutch = "Bekijk Replay"
        , esperanto = "Spektu Ripeton"
        }


i18nWhite : I18nToken String
i18nWhite =
    I18nToken
        { english = "White"
        , dutch = "Wit"
        , esperanto = "Blanko"
        }


i18nBlack : I18nToken String
i18nBlack =
    I18nToken
        { english = "Black"
        , dutch = "Zwart"
        , esperanto = "Nigro"
        }


i18nPlayerNamesForStreaming : I18nToken String
i18nPlayerNamesForStreaming =
    I18nToken
        { english = "Player names for streaming"
        , dutch = "Spelersnamen voor streaming"
        , esperanto = "Ludantnomoj por elsendfluo"
        }


i18nWhitePlayerName : I18nToken String
i18nWhitePlayerName =
    I18nToken
        { english = "Name of the White player"
        , dutch = "Naam speler wit"
        , esperanto = "Nomo de la Blanka ludanto"
        }


i18nBlackPlayerName : I18nToken String
i18nBlackPlayerName =
    I18nToken
        { english = "Name of the Black player"
        , dutch = "Naam speler zwart"
        , esperanto = "Nomo de la Nigra ludanto"
        }
