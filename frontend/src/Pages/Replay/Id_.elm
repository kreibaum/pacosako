module Pages.Replay.Id_ exposing (Model, Msg, Params, page)

{-| Watch replays of games that were played in /game/{id}

A lot of the messages can only work, once we have a replay loaded in.
This is why this page is written as two nested elm architectures, where
the outer one is responsible for loading the replay and the inner one
is responsible for displaying it / interacting with it.

-}

import Animation exposing (Timeline)
import Api.Backend exposing (Replay)
import Api.DecoderGen
import Api.EncoderGen
import Api.MessageGen
import Api.Ports
import Arrow exposing (Arrow)
import Browser.Navigation exposing (pushUrl)
import CastingDeco
import Colors
import Components
import Custom.Element exposing (icon)
import Custom.Events exposing (BoardMousePosition, KeyBinding, fireMsg, forKey)
import Custom.List as List
import Effect exposing (Effect)
import Element exposing (Element, alignTop, centerX, column, el, fill, fillPortion, height, padding, paddingXY, px, scrollbarY, spacing, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Element.Region
import Fen
import FontAwesome.Icon exposing (Icon)
import FontAwesome.Solid as Solid
import Gen.Route as Route
import Header
import Http
import List.Extra as List
import Notation
import Page
import Pages.NotFound
import PositionView exposing (OpaqueRenderData)
import Reactive
import Request
import Sako exposing (Color(..))
import Set
import Shared
import Svg.Custom as Svg exposing (BoardRotation(..))
import Time exposing (Posix)
import Translations as T
import Url
import View exposing (View)
import Api.ReplayMetaData exposing (ReplayMetaDataProcessed, ReplayCue(..))


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared { params } =
    Page.advanced
        { init = init shared params
        , update = update
        , subscriptions = subscriptions
        , view = view shared
        }



-- INIT


type alias Params =
    { id : String }


type alias Model =
    { replay : DataLoadingWrapper
    -- We store this inside & outside because of race conditions.
    , replayMetaData : ReplayMetaDataProcessed
    , actionHistory : List Sako.Action
    , key : String
    , navigationKey : Browser.Navigation.Key
    , now : Posix
    }


type alias InnerModel =
    { key : String
    , navigationKey : Browser.Navigation.Key
    , actionHistory : List Sako.Action
    , sidebarData : List Notation.HalfMove
    , replayMetaData : ReplayMetaDataProcessed
    , opening : String
    , selected : Notation.SectionIndex
    , timeline : Timeline OpaqueRenderData
    , castingDeco : CastingDeco.Model
    , inputMode : Maybe CastingDeco.InputMode
    , showMovementIndicators : Bool
    , animationSpeedSetting : AnimationSpeedSetting
    }


type DataLoadingWrapper
    = DownloadingReplayData
    | DownloadingReplayDataFailed Http.Error
    | ProcessingReplayData
    | Done InnerModel


init : Shared.Model -> Params -> ( Model, Effect Msg )
init shared params =
    ( { replay = DownloadingReplayData
      , replayMetaData = Api.ReplayMetaData.empty
      , actionHistory = []
      , key = params.id
      , navigationKey = shared.key
      , now = Time.millisToPosix 0
      }
    , Cmd.batch
        [ Api.Backend.getReplay params.id HttpErrorReplay GotReplay
        , Api.ReplayMetaData.getReplayMetaData params.id HttpErrorReplay GotReplayMetaData ]
        |> Effect.fromCmd
    )


type alias ReplayData =
    { notation : List Notation.HalfMove, opening : String }


{-| Init method that is called once the replay has been processed.
-}
innerInit : Model -> ReplayData -> InnerModel
innerInit model sidebarData =
    { key = model.key
    , navigationKey = model.navigationKey
    , actionHistory = model.actionHistory
    , sidebarData = sidebarData.notation
    , replayMetaData = model.replayMetaData
    , opening = sidebarData.opening
    , selected = Notation.initialSectionIndex
    , timeline = Animation.init (PositionView.renderStatic WhiteBottom Sako.initialPosition)
    , castingDeco = CastingDeco.initModel
    , inputMode = Nothing
    , showMovementIndicators = True
    , animationSpeedSetting = NormalAnimation
    }



-- UPDATE


type Msg
    = GotReplay Replay
    | GotReplayMetaData ReplayMetaDataProcessed
    | HttpErrorReplay Http.Error
    | HttpErrorMetaData Http.Error
    | GotReplayAnalysis { notation : List Notation.HalfMove, opening : String }
    | PortError String
    | ToShared Shared.Msg
    | GotInnerMsg InnerMsg


type InnerMsg
    = SetInputMode (Maybe CastingDeco.InputMode)
    | ClearDecoTiles
    | ClearDecoArrows
    | ClearDecoComplete
    | MouseDown CastingDeco.InputMode BoardMousePosition
    | MouseUp CastingDeco.InputMode BoardMousePosition
    | MouseMove CastingDeco.InputMode BoardMousePosition
    | CopyToClipboard String
    | NextAction
    | PreviousAction
    | NextMove
    | PreviousMove
    | GoToSelection Notation.SectionIndex
    | PlayAll
    | SetAnimationSpeedSetting AnimationSpeedSetting
    | EnableMovementIndicators
    | AnimationTick Posix
    | RematchFromActionIndex String Int
    | HttpErrorBranch Http.Error
    | GotBranchKey String


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        GotReplay replay ->
            ( { model
                | replay = ProcessingReplayData
                , actionHistory = removeTimestamps replay.actions
              }
            , replay
                |> stripDownReplay
                |> Api.EncoderGen.analyzeReplay
                |> Api.MessageGen.analyzeReplay
                |> Effect.fromCmd
            )

        GotReplayAnalysis notation ->
            ( { model
                | replay = Done (innerInit model notation)
              }
            , Effect.none
            )

        GotReplayMetaData replayMetaData ->
            ( { model | replayMetaData = Debug.log "ReplayMetaData" replayMetaData }
                |> copyReplayMetaDataIntoInner
            , Effect.none )

        HttpErrorReplay error ->
            ( { model | replay = DownloadingReplayDataFailed error }, Effect.none )


        HttpErrorMetaData error -> 
            ( { model | replayMetaData = Debug.log "ReplayMetaData" Api.ReplayMetaData.error }
                |> copyReplayMetaDataIntoInner
            , Effect.none )

        PortError error ->
            ( model, Api.Ports.logToConsole error |> Effect.fromCmd )

        ToShared outMsg ->
            ( model, Effect.fromShared outMsg )

        GotInnerMsg innerMsg ->
            case model.replay of
                Done innerModel ->
                    let
                        ( newInnerModel, innerEffect ) =
                            innerUpdate innerMsg innerModel
                    in
                    ( { model | replay = Done newInnerModel }, innerEffect |> Effect.map GotInnerMsg )

                _ ->
                    ( model, Effect.none )


innerUpdate : InnerMsg -> InnerModel -> ( InnerModel, Effect InnerMsg )
innerUpdate msg model =
    case msg of
        SetInputMode inputMode ->
            ( { model | inputMode = inputMode }, Effect.none )

        ClearDecoTiles ->
            ( { model | castingDeco = CastingDeco.clearTiles model.castingDeco }, Effect.none )

        ClearDecoArrows ->
            ( { model | castingDeco = CastingDeco.clearArrows model.castingDeco }, Effect.none )

        ClearDecoComplete ->
            ( { model | castingDeco = CastingDeco.initModel }, Effect.none )

        MouseDown mode pos ->
            ( { model | castingDeco = CastingDeco.mouseDown mode pos model.castingDeco }, Effect.none )

        MouseUp mode pos ->
            ( { model | castingDeco = CastingDeco.mouseUp mode pos model.castingDeco }, Effect.none )

        MouseMove mode pos ->
            ( { model | castingDeco = CastingDeco.mouseMove mode pos model.castingDeco }, Effect.none )

        CopyToClipboard text ->
            ( model, Api.Ports.copy text |> Effect.fromCmd )

        NextAction ->
            ( setAndAnimateActionCount (Notation.nextAction model.sidebarData model.selected) model, Effect.none )

        PreviousAction ->
            ( setAndAnimateActionCount (Notation.previousAction model.sidebarData model.selected) model, Effect.none )

        NextMove ->
            ( setAndAnimateActionCount (Notation.nextMove model.sidebarData model.selected) model, Effect.none )

        PreviousMove ->
            ( setAndAnimateActionCount (Notation.previousMove model.sidebarData model.selected) model, Effect.none )

        GoToSelection newSelection ->
            ( setAndAnimateActionCount newSelection model, Effect.none )

        PlayAll ->
            ( { model | showMovementIndicators = False }
                |> setAndAnimateActionCount Notation.initialSectionIndex
                |> animateStepByStep (Notation.lastSectionIndex model.sidebarData)
            , Effect.none
            )

        EnableMovementIndicators ->
            ( { model | showMovementIndicators = True }, Effect.none )

        AnimationTick now ->
            ( { model | timeline = Animation.tick now model.timeline }, Effect.none )

        RematchFromActionIndex key actionIndex ->
            ( model, Api.Backend.postRematchFromActionIndex key actionIndex Nothing HttpErrorBranch GotBranchKey |> Effect.fromCmd )

        HttpErrorBranch _ ->
            ( model, Api.Ports.logToConsole "Error branching game." |> Effect.fromCmd )

        GotBranchKey newKey ->
            ( model, pushUrl model.navigationKey (Route.toHref (Route.Game__Id_ { id = newKey })) |> Effect.fromCmd )

        SetAnimationSpeedSetting setting ->
            ( { model | animationSpeedSetting = setting }, Effect.none )


{-| Tells the inner model about the replay mata data from the outer model. -}
copyReplayMetaDataIntoInner : Model -> Model
copyReplayMetaDataIntoInner model = 
    case model.replay of
        Done innerModel ->
            { model | replay = Done { innerModel | replayMetaData = model.replayMetaData } }

        _ ->
            model


{-| Remove all the timestamps from the replay and turn it into an RpcCall.
-}
stripDownReplay :
    Replay
    ->
        { board_fen : String
        , action_history : List Sako.Action
        , setup : Api.Backend.SetupOptions
        }
stripDownReplay replay =
    { board_fen = Fen.initialBoardFen
    , action_history = removeTimestamps replay.actions
    , setup = replay.setupOptions
    }


removeTimestamps : List ( Sako.Action, Posix ) -> List Sako.Action
removeTimestamps actions =
    List.map Tuple.first actions


{-| Sets the action count to the given value and decides how to animate this.
Here are the rules:

  - If the new count is higher and all new actions are within the same move,
    then this is animated action by action.
  - Otherwise, the animation goes strait to the target state.

Note that we can't just put in this information from the place where we are
calling, because you can jump to any move at any time.

-}
setAndAnimateActionCount : Notation.SectionIndex -> InnerModel -> InnerModel
setAndAnimateActionCount newSelection model =
    let
        difference =
            Notation.sectionIndexDiff newSelection model.selected
    in
    if newSelection == model.selected then
        model

    else if not (Notation.sectionIndexDiffIsForward difference) then
        -- we jumped backwards
        animateDirect { model | selected = newSelection }

    else if difference.halfMoveIndex > 1 then
        -- This would jump too far ahead.
        animateDirect { model | selected = newSelection }

    else
        animateStepByStep newSelection model


{-| Tail recursive animation function that steps the timeline forward step by step.
-}
animateStepByStep : Notation.SectionIndex -> InnerModel -> InnerModel
animateStepByStep newSelection model =
    if Notation.sectionIndexDiff newSelection model.selected |> Notation.sectionIndexDiffIsForward then
        animateDirect { model | selected = Notation.nextAction model.sidebarData model.selected }
            |> (\m -> { m | timeline = Animation.pause (chainPauseTime model.animationSpeedSetting) m.timeline })
            |> animateStepByStep newSelection

    else
        model


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Custom.Events.onKeyUp keybindings |> Sub.map GotInnerMsg
        , case model.replay of
            Done innerModel ->
                Animation.subscription innerModel.timeline AnimationTick |> Sub.map GotInnerMsg

            _ ->
                Sub.none
        , Api.MessageGen.subscribePort PortError
            Api.MessageGen.replayAnalysisCompleted
            Api.DecoderGen.replayAnalysisCompleted
            GotReplayAnalysis
        ]


{-| The central pace to register all page wide shortcuts.
-}
keybindings : List (KeyBinding InnerMsg)
keybindings =
    [ forKey "1" |> fireMsg (SetInputMode Nothing)
    , forKey "2" |> fireMsg (SetInputMode (Just CastingDeco.InputTiles))
    , forKey "3" |> fireMsg (SetInputMode (Just CastingDeco.InputArrows))
    , forKey " " |> fireMsg ClearDecoComplete
    , forKey "0" |> fireMsg ClearDecoComplete
    , forKey "ArrowDown" |> fireMsg NextAction
    , forKey "ArrowUp" |> fireMsg PreviousAction
    , forKey "ArrowRight" |> fireMsg NextMove
    , forKey "ArrowLeft" |> fireMsg PreviousMove
    ]



-- VIEW


view : Shared.Model -> Model -> View Msg
view shared model =
    { title = T.watchReplayPageTitle
    , element =
        Header.wrapWithHeaderV2 shared
            ToShared
            { isRouteHighlighted = \_ -> False
            , isWithBackground = False
            }
            (body shared model)
    }



-- Constants


bg : { black : Element.Color, white : Element.Color, selected : Element.Color }
bg =
    { black = Element.rgb255 200 200 200
    , white = Element.rgb255 240 240 240
    , selected = Element.rgb255 220 255 220
    }


body : Shared.Model -> Model -> Element Msg
body shared model =
    case model.replay of
        DownloadingReplayData ->
            Element.text T.loadingReplayData

        DownloadingReplayDataFailed _ ->
            Pages.NotFound.body

        ProcessingReplayData ->
            Element.text T.loadingReplayData

        Done innerModel ->
            successBody shared innerModel
                |> Element.map GotInnerMsg


successBody : Shared.Model -> InnerModel -> Element InnerMsg
successBody shared model =
    case Reactive.classify shared.windowSize of
        Reactive.Phone ->
            successBodyPhone shared model

        Reactive.Tablet ->
            successBodyDesktop shared model

        Reactive.Desktop ->
            successBodyDesktop shared model


successBodyPhone : Shared.Model -> InnerModel -> Element InnerMsg
successBodyPhone shared model =
    el
        [ width fill, height fill, scrollbarY ]
        (column [ spacing 5, width fill ]
            [ boardView shared model
            , arrowButtons
            , Element.column
                [ width fill, height (fill |> Element.minimum 250), scrollbarY ]
                (setupButton model :: List.indexedMap (halfMoveRow model.selected) model.sidebarData)
            , opening model
            , column
                [ width fill, spacing 10, padding 10 ]
                [ enableMovementIndicators model.showMovementIndicators
                , editorLink model
                , rematchLink model
                , CastingDeco.configView
                    { setInputMode = SetInputMode
                    , clearTiles = ClearDecoTiles
                    , clearArrows = ClearDecoArrows
                    }
                    model.inputMode
                    model.castingDeco
                , Components.gameCodeLabel
                    (CopyToClipboard (Url.toString shared.url))
                    model.key
                , animationSpeedButtons model
                ]
            ]
        )


successBodyDesktop : Shared.Model -> InnerModel -> Element InnerMsg
successBodyDesktop shared model =
    el [ centerX, height fill, width (Element.maximum 1120 fill) ]
        (Element.row
            [ width fill, height fill, paddingXY 10 0, spacing 10 ]
            [ column [ width fill, height fill ] [ boardView shared model ]
            , Element.column [ spacing 10, padding 10, alignTop, height fill, width (px 250) ]
                (sidebarContent shared model)
            ]
        )



--------------------------------------------------------------------------------
-- Board View ------------------------------------------------------------------
--------------------------------------------------------------------------------


type AnimationSpeedSetting
    = FastAnimation
    | NormalAnimation
    | SlowAnimation


{-| Time to move from one board state to the next.
-}
motionTime : AnimationSpeedSetting -> Animation.Duration
motionTime setting =
    case setting of
        FastAnimation ->
            Animation.milliseconds 100

        NormalAnimation ->
            Animation.milliseconds 200

        SlowAnimation ->
            Animation.milliseconds 300


{-| Pause between two actions in a chain.
-}
chainPauseTime : AnimationSpeedSetting -> Animation.Duration
chainPauseTime setting =
    case setting of
        FastAnimation ->
            Animation.milliseconds 50

        NormalAnimation ->
            Animation.milliseconds 150

        SlowAnimation ->
            Animation.milliseconds 500


{-| Given a model where the timeline does not match the actionCount, this adds
an animation to the timeline which transitions to the correct actionCount view.

While this is technically an update function, it is closely related to the board
view so I am putting it in this section.

-}
animateDirect : InnerModel -> InnerModel
animateDirect model =
    animateDirectR model
        |> Maybe.map (\renderData -> { model | timeline = Animation.queue ( motionTime model.animationSpeedSetting, renderData ) model.timeline })
        |> Maybe.withDefault model


animateDirectR : InnerModel -> Maybe OpaqueRenderData
animateDirectR model =
    let
        board =
            currentBoard model
    in
    case board of
        ReplayOk boardOk _ ->
            Just (PositionView.renderStatic Svg.WhiteBottom boardOk)

        ReplayToShort ->
            Nothing

        ReplayError ->
            Nothing


{-| Show the game state at `model.actionCount`.
-}
boardView : Shared.Model -> InnerModel -> Element InnerMsg
boardView shared model =
    case currentBoard model of
        ReplayOk position partialActionHistory ->
            Element.el
                [ width fill
                , height fill
                , centerX
                ]
                (boardViewOk shared model position partialActionHistory)

        ReplayToShort ->
            Element.text "Replay is corrupted, too short :-("

        ReplayError ->
            Element.text "Replay is corrupted, rule violation :-("


type BoardReplayState
    = ReplayOk Sako.Position (List Sako.Action)
    | ReplayToShort
    | ReplayError


currentBoard : InnerModel -> BoardReplayState
currentBoard model =
    let
        actionIndex =
            Notation.actionIndexForSectionIndex model.sidebarData model.selected

        actions =
            List.take actionIndex model.actionHistory
    in
    if List.length actions == actionIndex then
        Sako.doActionsList actions Sako.initialPosition
            |> Maybe.map (\x -> ReplayOk x actions)
            |> Maybe.withDefault ReplayError

    else
        ReplayToShort


boardViewOk : Shared.Model -> InnerModel -> Sako.Position -> List Sako.Action -> Element InnerMsg
boardViewOk shared model position partialActionHistory =
    PositionView.viewTimeline
        { colorScheme =
            Colors.configToOptions shared.colorConfig
        , nodeId = Nothing
        , decoration = decoration model position partialActionHistory
            ++ metaDataDecoration model
        , dragPieceData = []
        , mouseDown = Maybe.map MouseDown model.inputMode
        , mouseUp = Maybe.map MouseUp model.inputMode
        , mouseMove = Maybe.map MouseMove model.inputMode
        , additionalSvg = Nothing
        , replaceViewport =
            Just
                { x = -10
                , y = -10
                , width = 820
                , height = 820
                }
        }
        model.timeline


decoration : InnerModel -> Sako.Position -> List Sako.Action -> List PositionView.BoardDecoration
decoration model position partialActionHistory =
    if model.showMovementIndicators then
        CastingDeco.toDecoration PositionView.castingDecoMappers model.castingDeco
            ++ (PositionView.pastMovementIndicatorList position partialActionHistory
                    |> List.map PositionView.PastMovementIndicator
               )

    else
        CastingDeco.toDecoration PositionView.castingDecoMappers model.castingDeco

metaDataDecoration : InnerModel -> List PositionView.BoardDecoration
metaDataDecoration model =
    let
        actionIndex =
            Notation.actionIndexForSectionIndex model.sidebarData model.selected
                |> Debug.log "Action Index"
    in 
    Api.ReplayMetaData.filter (Set.fromList ["Example Arrow"]) actionIndex model.replayMetaData
        |> List.filterMap oneMetaDataDecoration

oneMetaDataDecoration : ReplayCue -> Maybe PositionView.BoardDecoration
oneMetaDataDecoration cue =
    case cue of
        CueString _ ->
            Nothing
        CueArrow { start, end } -> 
            Just( PositionView.CastingArrow { head = end , tail = start } )

--------------------------------------------------------------------------------
-- Sidebar ---------------------------------------------------------------------
--------------------------------------------------------------------------------


sidebarContent : Shared.Model -> InnerModel -> List (Element InnerMsg)
sidebarContent shared model =
    [ Components.gameCodeLabel
        (CopyToClipboard (Url.toString shared.url))
        model.key
    , arrowButtons
    , animationSpeedButtons model
    , Element.text T.orUseArrows
    , enableMovementIndicators model.showMovementIndicators
    , editorLink model
    , rematchLink model
    , opening model
    , actionList model
    , CastingDeco.configView
        { setInputMode = SetInputMode
        , clearTiles = ClearDecoTiles
        , clearArrows = ClearDecoArrows
        }
        model.inputMode
        model.castingDeco
    ]


opening : InnerModel -> Element InnerMsg
opening model =
    if String.isEmpty model.opening then
        Element.none

    else
        Element.paragraph [] [ Element.text model.opening, Element.text T.replayWithOpening ]


arrowButtons : Element InnerMsg
arrowButtons =
    Element.row [ spacing 5, width fill, paddingXY 5 0 ]
        [ sharedWidthControll False T.replayPreviousMove Solid.arrowLeft (Just PreviousMove)
        , sharedWidthControll False T.replayPreviousAction Solid.chevronLeft (Just PreviousAction)
        , sharedWidthControll False T.replayPlayAll Solid.play (Just PlayAll)
        , sharedWidthControll False T.replayNextAction Solid.chevronRight (Just NextAction)
        , sharedWidthControll False T.replayNextMove Solid.arrowRight (Just NextMove)
        ]


sharedWidthControll : Bool -> String -> Icon -> Maybe msg -> Element msg
sharedWidthControll isSelected altText iconType msg =
    Input.button
        [ width fill
        , Background.color
            (if isSelected then
                Element.rgb255 200 200 200

             else
                Element.rgb255 240 240 240
            )
        , Element.mouseOver [ Background.color (Element.rgb255 220 220 220) ]
        , Border.rounded 5
        ]
        { onPress = msg
        , label = icon [ centerX, padding 5, Element.Region.description altText ] iconType
        }


animationSpeedButtons : InnerModel -> Element InnerMsg
animationSpeedButtons model =
    Element.row [ spacing 5, width fill, paddingXY 5 0 ]
        [ sharedWidthControll (model.animationSpeedSetting == SlowAnimation) T.replayPreviousMove Solid.snowflake (Just (SetAnimationSpeedSetting SlowAnimation))
        , sharedWidthControll (model.animationSpeedSetting == NormalAnimation) T.replayPreviousAction Solid.frog (Just (SetAnimationSpeedSetting NormalAnimation))
        , sharedWidthControll (model.animationSpeedSetting == FastAnimation) T.replayPlayAll Solid.spaceShuttle (Just (SetAnimationSpeedSetting FastAnimation))
        ]


enableMovementIndicators : Bool -> Element InnerMsg
enableMovementIndicators showMovementIndicators =
    if showMovementIndicators then
        Element.none

    else
        Input.button []
            { onPress = Just EnableMovementIndicators
            , label =
                Element.row [ spacing 10 ]
                    [ Custom.Element.icon [] Solid.eye, Element.text T.showMovementIndicators ]
            }


editorLink : InnerModel -> Element msg
editorLink model =
    let
        actionIndex =
            Notation.actionIndexForSectionIndex model.sidebarData model.selected
    in
    Element.link [ Font.underline, Font.color (Element.rgb 0 0 1) ]
        { url =
            Route.toHref Route.Editor
                ++ "?game="
                ++ model.key
                ++ "&action="
                ++ String.fromInt actionIndex
        , label = Element.text T.replayShowInEditor
        }


rematchLink : InnerModel -> Element InnerMsg
rematchLink model =
    let
        actionIndex =
            Notation.actionIndexForSectionIndex model.sidebarData model.selected
    in
    Input.button [ Font.underline, Font.color (Element.rgb 0 0 1) ]
        { onPress = Just <| RematchFromActionIndex model.key actionIndex
        , label = Element.text T.replayRematchFromHere
        }


{-| The interactive list of all action that happened in the game. You can click
on one action go to to that position.
-}
actionList : InnerModel -> Element InnerMsg
actionList model =
    Element.column [ width fill, height fill, scrollbarY ]
        (setupButton model :: List.indexedMap (halfMoveRow model.selected) model.sidebarData)


{-| Button that brings you to actionCount == 0, i.e. an inital board state.
-}
setupButton : InnerModel -> Element InnerMsg
setupButton model =
    let
        attrs =
            if model.selected == Notation.initialSectionIndex then
                [ Background.color (Element.rgb255 51 191 255), padding 5, width fill ]

            else
                [ Element.mouseOver
                    [ Background.color (Element.rgb255 102 206 255)
                    , Background.color bg.black
                    ]
                , Background.color bg.black
                , padding 5
                , width fill
                ]
    in
    Input.button attrs
        { onPress = Just (GoToSelection Notation.initialSectionIndex)
        , label = Element.text T.replayRestart
        }


{-| Renders one half move like:

9 e7>Nf6>Bd7>b5

-}
halfMoveRow : Notation.SectionIndex -> Int -> Notation.HalfMove -> Element InnerMsg
halfMoveRow currentlySelected halfMoveIndex moveData =
    Element.row [ width fill, moveBackground moveData.current_player ]
        [ halfMoveRowMainLabel halfMoveIndex moveData
        , Element.wrappedRow [ width (fillPortion 4) ]
            (List.indexedMap (sidebarAction currentlySelected halfMoveIndex) moveData.actions
                ++ [ givesOpponentPacoOpportunityLabel moveData, missedPacoLabel moveData, givesSakoLabel moveData ]
            )
        ]


givesOpponentPacoOpportunityLabel : Notation.HalfMove -> Element msg
givesOpponentPacoOpportunityLabel moveData =
    if moveData.metadata.givesOpponentPacoOpportunity then
        el [ Element.alignRight, paddingXY 2 0, Font.bold, Font.color (Element.rgb255 0 0 0) ] (Element.text "??")

    else
        Element.none


givesSakoLabel : Notation.HalfMove -> Element msg
givesSakoLabel moveData =
    if moveData.metadata.givesSako then
        el [ Element.alignRight, paddingXY 2 0, Font.bold, Font.color (Element.rgb255 85 153 85) ] (Element.text "Ŝ")

    else
        Element.none


missedPacoLabel : Notation.HalfMove -> Element msg
missedPacoLabel moveData =
    if moveData.metadata.missedPaco then
        el [ Element.alignRight, paddingXY 2 0, Font.bold, Font.color (Element.rgb255 153 86 86) ] (Element.text "P")

    else
        Element.none


{-| Left side, summarizes all action of a move into a single block.
You can click this block to go to the end of the whole move block.
-}
halfMoveRowMainLabel : Int -> Notation.HalfMove -> Element InnerMsg
halfMoveRowMainLabel halfMoveIndex halfMove =
    Input.button [ height fill, width (fillPortion 1), paddingXY 5 0 ]
        { onPress =
            Notation.lastSectionIndexOfHalfMove halfMoveIndex halfMove
                |> GoToSelection
                |> Just
        , label = Element.text (String.fromInt halfMove.moveNumber)
        }


{-| Tells the user if the move was done by white or by black.
-}
moveBackground : Sako.Color -> Element.Attribute msg
moveBackground color =
    case color of
        White ->
            Background.color bg.white

        Black ->
            Background.color bg.black


{-| Shows a single action and will take you to it.
-}
sidebarAction : Notation.SectionIndex -> Int -> Int -> Notation.HalfMoveSection -> Element InnerMsg
sidebarAction currentlySelected halfMoveIndex sectionIndex halfMoveSection =
    let
        newSelection =
            { halfMoveIndex = halfMoveIndex, sectionIndex = sectionIndex }

        attrs =
            if currentlySelected == newSelection then
                [ Background.color (Element.rgb255 51 191 255), paddingXY 0 5 ]

            else
                [ paddingXY 0 5
                , Element.mouseOver [ Background.color (Element.rgb255 102 206 255) ]
                ]
    in
    Input.button attrs
        { onPress = Just (GoToSelection newSelection)
        , label = Element.text halfMoveSection.label
        }
