module Pages.Game.Id_String exposing (Model, Msg, Params, page)

import Animation exposing (Timeline)
import Api.Ai
import Api.Backend
import Api.Ports as Ports
import Api.Websocket exposing (CurrentMatchState)
import Arrow exposing (Arrow)
import Browser
import Browser.Events
import CastingDeco
import Components
import Custom.Element exposing (icon)
import Custom.Events exposing (BoardMousePosition, KeyBinding, fireMsg, forKey)
import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import File.Download
import FontAwesome.Icon exposing (Icon)
import FontAwesome.Regular as Regular
import FontAwesome.Solid as Solid
import Html exposing (Html)
import Http
import I18n.Strings as I18n exposing (Language(..), t)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import List.Extra as List
import Maybe.Extra as Maybe
import Pieces
import PositionView exposing (BoardDecoration(..), DragPieceData, DragState, DraggingPieces(..), Highlight(..), OpaqueRenderData, nextHighlight)
import Reactive exposing (Device(..))
import RemoteData exposing (RemoteData, WebData)
import Result.Extra as Result
import Sako exposing (Piece, Tile(..))
import SaveState exposing (SaveState(..), saveStateId, saveStateModify, saveStateStored)
import Shared
import Spa.Document exposing (Document)
import Spa.Generated.Route as Route
import Spa.Page as Page exposing (Page)
import Spa.Url as Url exposing (Url)
import Svg exposing (Svg)
import Svg.Attributes as SvgA
import Svg.Custom as Svg exposing (BoardRotation(..))
import Time exposing (Posix)
import Timer


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

    -- later: , preview : Maybe Sako.Position
    , timeline : Timeline OpaqueRenderData
    , focus : Maybe Tile
    , dragState : DragState
    , castingDeco : CastingDeco.Model
    , inputMode : Maybe CastingDeco.InputMode
    , rotation : BoardRotation
    , now : Posix
    }


init : Shared.Model -> Url Params -> ( Model, Cmd Msg )
init shared { params } =
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
      , now = Time.millisToPosix 0
      }
    , Api.Websocket.send (Api.Websocket.SubscribeToMatch (Debug.log "game-id" params.id))
    )



-- UPDATE


type Msg
    = PlayActionInputStep Sako.Action
    | PlayRollback
    | PlayMsgAnimationTick Posix
    | PlayMouseDown BoardMousePosition
    | PlayMouseUp BoardMousePosition
    | PlayMouseMove BoardMousePosition
    | SetInputModePlay (Maybe CastingDeco.InputMode)
    | ClearDecoTilesPlay
    | ClearDecoArrowsPlay
    | ClearDecoComplete
    | MoveFromAi Sako.Action
    | RequestAiMove
    | AiCrashed
    | SetRotation BoardRotation
    | UpdateNow Posix
    | WebsocketMsg Api.Websocket.ServerMessage
    | WebsocketErrorMsg Decode.Error


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        PlayActionInputStep action ->
            updateActionInputStep action model

        PlayMsgAnimationTick now ->
            ( { model | timeline = Animation.tick now model.timeline }, Cmd.none )

        PlayRollback ->
            ( model
            , Api.Websocket.send (Api.Websocket.Rollback (Maybe.withDefault "" model.subscription))
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

        UpdateNow now ->
            ( { model | now = now }, Cmd.none )

        WebsocketMsg serverMessage ->
            updateWebsocket serverMessage model

        WebsocketErrorMsg error ->
            ( model, Ports.logToConsole (Decode.errorToString error) )


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
            , Cmd.none
            )


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
updatePlayCurrentMatchStateIfKeyCorrect : CurrentMatchState -> Model -> ( Model, Cmd Msg )
updatePlayCurrentMatchStateIfKeyCorrect data model =
    if data.key == model.currentState.key then
        updatePlayCurrentMatchState data model

    else
        ( model, Cmd.none )


updatePlayCurrentMatchState : CurrentMatchState -> Model -> ( Model, Cmd Msg )
updatePlayCurrentMatchState data model =
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


updatePlayMatchConnectionSuccess : { key : String, state : CurrentMatchState } -> Model -> ( Model, Cmd Msg )
updatePlayMatchConnectionSuccess data model =
    { model | subscription = Just data.key }
        |> updatePlayCurrentMatchState data.state


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

        Api.Websocket.FullState syncronizedBoard ->
            -- let
            --     ( newEditor, cmd ) =
            --         updateEditorWebsocketFullState syncronizedBoard model.editor
            -- in
            -- ( { model | editor = newEditor }, cmd )
            ( model, Cmd.none )

        Api.Websocket.ServerNextStep { index, step } ->
            -- let
            --     ( newEditor, cmd ) =
            --         updateWebsocketNextStep index step model.editor
            -- in
            -- ( { model | editor = newEditor }, cmd )
            ( model, Cmd.none )

        Api.Websocket.NewMatchState data ->
            updatePlayCurrentMatchStateIfKeyCorrect data model

        Api.Websocket.MatchConnectionSuccess data ->
            updatePlayMatchConnectionSuccess data model


save : Model -> Shared.Model -> Shared.Model
save model shared =
    shared


load : Shared.Model -> Model -> ( Model, Cmd Msg )
load shared model =
    ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every 1000 UpdateNow
        , Animation.subscription model.timeline PlayMsgAnimationTick
        , Api.Websocket.listen WebsocketMsg WebsocketErrorMsg
        , Api.Ai.subscribeMoveFromAi AiCrashed MoveFromAi
        , Custom.Events.onKeyUp keybindings
        ]


{-| The central pace to register all page wide shortcuts.
-}
keybindings : List (KeyBinding Msg)
keybindings =
    [ forKey "1" |> fireMsg (SetInputModePlay Nothing)
    , forKey "2" |> fireMsg (SetInputModePlay (Just CastingDeco.InputTiles))
    , forKey "3" |> fireMsg (SetInputModePlay (Just CastingDeco.InputArrows))
    , forKey " " |> fireMsg ClearDecoComplete
    , forKey "0" |> fireMsg ClearDecoComplete
    ]



-- VIEW


view : Model -> Document Msg
view model =
    { title = "Play Paco Ŝako - pacoplay.com"
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
playPositionView play =
    Element.el [ width fill, height fill ]
        (PositionView.viewTimeline
            { colorScheme = Pieces.defaultColorScheme
            , nodeId = Just sakoEditorId
            , decoration = playDecoration play
            , dragPieceData = []
            , mouseDown = Just PlayMouseDown
            , mouseUp = Just PlayMouseUp
            , mouseMove = Just PlayMouseMove
            , additionalSvg = playTimerSvg play.now play
            , replaceViewport = playTimerReplaceViewport play
            }
            play.timeline
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


playTimerSvg : Posix -> Model -> Maybe (Svg a)
playTimerSvg now model =
    model.currentState.timer
        |> Maybe.map (justPlayTimerSvg now model)


justPlayTimerSvg : Posix -> Model -> Timer.Timer -> Svg a
justPlayTimerSvg now model timer =
    let
        viewData =
            Timer.render model.currentState.controllingPlayer now timer
    in
    Svg.g []
        [ timerTagSvg
            { caption = timeLabel viewData.secondsLeftWhite
            , player = Sako.White
            , at = Svg.Coord 0 (timerLabelYPosition model.rotation Sako.White)
            }
        , timerTagSvg
            { caption = timeLabel viewData.secondsLeftBlack
            , player = Sako.Black
            , at = Svg.Coord 0 (timerLabelYPosition model.rotation Sako.Black)
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
    Model
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


sidebar : Model -> Element Msg
sidebar model =
    Element.column [ spacing 5, padding 20, height fill ]
        [ gameCodeLabel model.subscription
        , bigRoundedButton (Element.rgb255 220 220 220)
            (Just PlayRollback)
            [ Element.text "Restart Move" ]
            |> Element.el [ width fill ]
        , maybePromotionButtons model.currentState.legalActions
        , maybeVictoryStateInfo model.currentState.gameState
        , maybeReplayLink model
        , Element.el [ padding 10 ] Element.none
        , CastingDeco.configView castingDecoMessagesPlay model.inputMode model.castingDeco
        , Element.el [ padding 10 ] Element.none
        , Element.text "Play as:"
        , rotationButtons model.rotation

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


castingDecoMessagesPlay : CastingDeco.Messages Msg
castingDecoMessagesPlay =
    { setInputMode = SetInputModePlay
    , clearTiles = ClearDecoTilesPlay
    , clearArrows = ClearDecoArrowsPlay
    }


gameCodeLabel : Maybe String -> Element msg
gameCodeLabel subscription =
    case subscription of
        Just id ->
            Element.column [ width fill, spacing 5 ]
                [ Components.gameIdBadgeBig id
                , Element.text "Share this id with a friend."
                ]

        Nothing ->
            Element.text "Not connected"


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
                (Just (PlayActionInputStep (Sako.Promote Sako.Queen)))
                [ icon [ centerX ] Solid.chessQueen
                , Element.el [ centerX ] (Element.text "Queen")
                ]
            , bigRoundedButton (Element.rgb255 200 240 200)
                (Just (PlayActionInputStep (Sako.Promote Sako.Knight)))
                [ icon [ centerX ] Solid.chessKnight
                , Element.el [ centerX ] (Element.text "Knight")
                ]
            ]
        , Element.row [ width fill, spacing 5 ]
            [ bigRoundedButton (Element.rgb255 200 240 200)
                (Just (PlayActionInputStep (Sako.Promote Sako.Rook)))
                [ icon [ centerX ] Solid.chessRook
                , Element.el [ centerX ] (Element.text "Rook")
                ]
            , bigRoundedButton (Element.rgb255 200 240 200)
                (Just (PlayActionInputStep (Sako.Promote Sako.Bishop)))
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
                            , label = Element.text "Watch Replay"
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


rotationButtons : BoardRotation -> Element Msg
rotationButtons rotation =
    Element.row [ spacing 10 ]
        [ rotationButton WhiteBottom rotation "White"
        , rotationButton BlackBottom rotation "Black"
        ]


rotationButton : BoardRotation -> BoardRotation -> String -> Element Msg
rotationButton rotation currentRotation label =
    if rotation == currentRotation then
        Input.button
            [ Background.color (Element.rgb255 200 200 200), padding 3 ]
            { onPress = Nothing, label = Element.text label }

    else
        Input.button
            [ padding 3 ]
            { onPress = Just (SetRotation rotation), label = Element.text label }
