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
import Custom.Element exposing (icon)
import Custom.Events exposing (BoardMousePosition)
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
import PositionView exposing (BoardDecoration(..), DragPieceData, DragState, DraggingPieces(..), Highlight(..), OpaqueRenderData, coordinateOfTile, nextHighlight)
import Reactive exposing (Device(..))
import RemoteData exposing (RemoteData, WebData)
import Result.Extra as Result
import Sako exposing (Piece, Tile(..))
import SaveState exposing (SaveState(..), saveStateId, saveStateModify, saveStateStored)
import Shared
import Spa.Document exposing (Document, LegacyPage(..))
import Spa.Page as Page
import Spa.Url exposing (Url)
import Svg exposing (Svg)
import Svg.Attributes as SvgA
import Svg.Custom as Svg
import Time exposing (Posix)
import Timer


type alias Params =
    ()


type alias Model =
    { taco : Taco
    , page : LegacyPage
    , play : PlayModel
    , matchSetup : MatchSetupModel
    , language : Language

    -- , url : Url Params
    }


type Msg
    = PlayMsgWrapper PlayMsg
    | MatchSetupMsgWrapper MatchSetupMsg
    | OpenPage LegacyPage
    | HttpError Http.Error
    | WebsocketMsg Websocket.ServerMessage
    | WebsocketErrorMsg Decode.Error
    | UpdateNow Posix
    | WindowResize Int Int


page : Page.Page Params Model Msg
page =
    Page.application
        { init = \shared params -> init shared
        , update = update
        , view = view
        , subscriptions = subscriptions
        , save = save
        , load = load
        }


view : Model -> Document Msg
view model =
    { title = "Paco Ŝako"
    , body = [ globalUi model ]
    }


save : Model -> Shared.Model -> Shared.Model
save model shared =
    { shared
        | legacyPage = model.page
        , user = model.taco.login
    }


load : Shared.Model -> Model -> ( Model, Cmd Msg )
load shared model =
    let
        oldTaco =
            model.taco
    in
    ( { model | page = shared.legacyPage, taco = { oldTaco | login = shared.user } }
    , refreshRecentGames
    )



--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- All of my old code from Main.elm --------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------


type alias User =
    { id : Int
    , username : String
    }


type alias Taco =
    { login : Maybe User
    , now : Posix
    }


initialTaco : Shared.Model -> Taco
initialTaco shared =
    { login = shared.user, now = Time.millisToPosix 0 }


init : Shared.Model -> ( Model, Cmd Msg )
init shared =
    ( { taco = initialTaco shared
      , page = shared.legacyPage
      , play = initPlayModel shared.windowSize
      , matchSetup = initMatchSetupModel
      , language = I18n.English
      }
    , refreshRecentGames
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
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

        OpenPage newPage ->
            ( { model | page = newPage }
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
                oldPlay =
                    model.play
            in
            ( { model
                | play = { oldPlay | windowSize = ( width, height ) }
              }
            , Cmd.none
            )



--------------------------------------------------------------------------------
-- Handle websocket messages ---------------------------------------------------
--------------------------------------------------------------------------------


updateWebsocket : Websocket.ServerMessage -> Model -> ( Model, Cmd Msg )
updateWebsocket serverMessage model =
    case serverMessage of
        Websocket.TechnicalError errorMessage ->
            ( model, Ports.logToConsole errorMessage )

        Websocket.FullState syncronizedBoard ->
            -- let
            --     ( newEditor, cmd ) =
            --         updateEditorWebsocketFullState syncronizedBoard model.editor
            -- in
            -- ( { model | editor = newEditor }, cmd )
            ( model, Cmd.none )

        Websocket.ServerNextStep { index, step } ->
            -- let
            --     ( newEditor, cmd ) =
            --         updateWebsocketNextStep index step model.editor
            -- in
            -- ( { model | editor = newEditor }, cmd )
            ( model, Cmd.none )

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


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Browser.Events.onResize WindowResize
        , Websocket.listen WebsocketMsg WebsocketErrorMsg
        , Animation.subscription model.play.timeline (PlayMsgAnimationTick >> PlayMsgWrapper)
        , Time.every 1000 UpdateNow
        , Api.Ai.subscribeMoveFromAi (PlayMsgWrapper AiCrashed) (MoveFromAi >> PlayMsgWrapper)
        ]



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

        _ ->
            Element.text "Error - This page should not be accessed this way."



--------------------------------------------------------------------------------
-- Editor viev -----------------------------------------------------------------
--------------------------------------------------------------------------------


castingDecoMappers : { tile : Tile -> BoardDecoration, arrow : Arrow -> BoardDecoration }
castingDecoMappers =
    { tile = CastingHighlight
    , arrow = CastingArrow
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
    Element.row
        [ width fill, height fill, Element.scrollbarY ]
        [ playPositionView taco model
        , playModeSidebar taco model
        ]


playUiPortrait : Taco -> PlayModel -> Element Msg
playUiPortrait taco model =
    Element.column
        [ width fill, height fill ]
        [ playPositionView taco model
        , playModeSidebar taco model
        ]


playPositionView : Taco -> PlayModel -> Element Msg
playPositionView taco play =
    Element.el [ width fill, height fill ]
        (PositionView.viewTimeline
            { colorScheme = Pieces.defaultColorScheme
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


sakoEditorId : String
sakoEditorId =
    "sako-editor"


playDecoration : PlayModel -> List PositionView.BoardDecoration
playDecoration play =
    (play.currentState.legalActions
        |> List.filterMap actionDecoration
    )
        ++ playViewHighlight play
        ++ CastingDeco.toDecoration castingDecoMappers play.castingDeco
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
    Element.column [ width fill, height fill, scrollbarY ]
        [ Element.el [ padding 40, centerX, Font.size 40 ] (Element.text "Play Paco Ŝako")
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
        , Input.text [ width fill, Custom.Events.onEnter (JoinMatch |> MatchSetupMsgWrapper) ]
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
