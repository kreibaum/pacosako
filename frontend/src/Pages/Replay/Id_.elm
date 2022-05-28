module Pages.Replay.Id_ exposing (Model, Msg, Params, page)

{-| Watch replays of games that were played in /game/{id}
-}

import Animation exposing (Timeline)
import Api.Backend exposing (Replay)
import Api.Ports
import Browser.Navigation exposing (pushUrl)
import CastingDeco
import Colors
import Components
import Custom.Events exposing (BoardMousePosition, KeyBinding, fireMsg, forKey)
import Custom.List as List
import Effect exposing (Effect)
import Element exposing (Element, alignTop, centerX, column, el, fill, fillPortion, height, padding, paddingXY, px, scrollbarY, spacing, width)
import Element.Background as Background
import Element.Font as Font
import Element.Input as Input
import FontAwesome.Solid as Solid
import Gen.Route as Route
import Header
import Http
import List.Extra as List
import Notation
import Page
import Pages.NotFound
import PositionView exposing (OpaqueRenderData)
import RemoteData exposing (WebData)
import Request
import Sako exposing (Color(..))
import Shared
import Svg.Custom as Svg exposing (BoardRotation(..))
import Time exposing (Posix)
import Translations as T
import Url
import View exposing (View)


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
    { replay : WebData Replay
    , sidebarData : List Notation.SidebarMoveData
    , key : String
    , navigationKey : Browser.Navigation.Key
    , actionCount : Int
    , timeline : Timeline OpaqueRenderData
    , now : Posix
    , castingDeco : CastingDeco.Model
    , inputMode : Maybe CastingDeco.InputMode
    , showMovementIndicators : Bool
    }


init : Shared.Model -> Params -> ( Model, Effect Msg )
init shared params =
    ( { replay = RemoteData.Loading
      , sidebarData = []
      , key = params.id
      , navigationKey = shared.key
      , actionCount = 0
      , timeline = Animation.init (PositionView.renderStatic WhiteBottom Sako.initialPosition)
      , now = Time.millisToPosix 0
      , castingDeco = CastingDeco.initModel
      , inputMode = Nothing
      , showMovementIndicators = True
      }
    , Api.Backend.getReplay params.id HttpErrorReplay GotReplay |> Effect.fromCmd
    )



-- UPDATE


type Msg
    = GotReplay Replay
    | HttpErrorReplay Http.Error
    | GoToActionCount Int
    | SetInputMode (Maybe CastingDeco.InputMode)
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
    | PlayAll
    | EnableMovementIndicators
    | AnimationTick Posix
    | RematchFromActionIndex String Int
    | HttpErrorBranch Http.Error
    | GotBranchKey String
    | ToShared Shared.Msg


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        GotReplay replay ->
            ( { model
                | replay = RemoteData.Success replay
                , sidebarData = Notation.compile replay
              }
            , Effect.none
            )

        HttpErrorReplay error ->
            ( { model | replay = RemoteData.Failure error }, Effect.none )

        GoToActionCount actionCount ->
            ( setAndAnimateActionCount actionCount model, Effect.none )

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
            ( setAndAnimateActionCount (nextAction model) model, Effect.none )

        PreviousAction ->
            ( setAndAnimateActionCount (previousAction model) model, Effect.none )

        NextMove ->
            ( setAndAnimateActionCount (nextMove model) model, Effect.none )

        PreviousMove ->
            ( setAndAnimateActionCount (previousMove model) model, Effect.none )

        PlayAll ->
            ( { model | showMovementIndicators = False }
                |> setAndAnimateActionCount 0
                |> animateStepByStep (Notation.lastAction model.sidebarData)
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

        ToShared outMsg ->
            ( model, Effect.fromShared outMsg )


{-| Sets the action count to the given value and decides how to animate this.
Here are the rules:

  - If the new count is higher and all new actions are within the same move,
    then this is animated action by action.
  - Otherwise, the animation goes strait to the target state.

Note that we can't just put in this information from the place where we are
calling, because you can jump to any move at any time.

-}
setAndAnimateActionCount : Int -> Model -> Model
setAndAnimateActionCount actionCount model =
    let
        currentMoveNumber =
            Notation.moveContainingAction model.actionCount model.sidebarData
                |> Maybe.map .moveNumber
                |> Maybe.withDefault -42
                |> Debug.log "currentMoveNumber"

        targetMoveNumber =
            Notation.moveContainingAction actionCount model.sidebarData
                |> Maybe.map .moveNumber
                |> Maybe.withDefault -1337
                |> Debug.log "targetMoveNumber"
    in
    if actionCount < model.actionCount then
        -- we jumped backwards
        animateDirect { model | actionCount = actionCount }

    else if currentMoveNumber + 1 < targetMoveNumber then
        -- This would jump too far ahead.
        animateDirect { model | actionCount = actionCount }

    else
        animateStepByStep actionCount model


{-| Tail recursive animation function that steps the timeline forward step by step.
-}
animateStepByStep : Int -> Model -> Model
animateStepByStep actionCount model =
    if model.actionCount >= actionCount then
        model

    else
        animateDirect { model | actionCount = nextAction model }
            |> (\m -> { m | timeline = Animation.pause chainPauseTime m.timeline })
            |> animateStepByStep actionCount


{-| Just increases the actionCount by one and makes sure not to go above the
limit.
-}
nextAction : Model -> Int
nextAction model =
    Notation.firstActionCountAfterIndex model.actionCount model.sidebarData
        |> Maybe.withDefault model.actionCount


{-| Just decreases the actionCount by one and makes sure it does not go below
zero.
-}
previousAction : Model -> Int
previousAction model =
    Notation.lastActionCountBeforeIndex model.actionCount model.sidebarData


{-| Finds the first move that is not already completely shown by the current
actionCount and then goes to the last action of this move.
-}
nextMove : Model -> Int
nextMove model =
    let
        actionCount =
            model.sidebarData
                |> List.find (\move -> Notation.lastActionCountOf move > model.actionCount)
                |> Maybe.map Notation.lastActionCountOf
                |> Maybe.withDefault model.actionCount
    in
    actionCount


{-| Finds the first move that is not already partially shown by the current
actionCount and then goes to the last action of this move.
If the first move is already partially shown, then this goes back to the start
which is actionCount 0.
-}
previousMove : Model -> Int
previousMove model =
    let
        actionCount =
            model.sidebarData
                |> List.find (\move -> Notation.lastActionCountOf move >= model.actionCount)
                |> Maybe.map (\move -> Notation.lastActionCountBefore move)
                |> Maybe.withDefault 0
    in
    actionCount


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Custom.Events.onKeyUp keybindings
        , Animation.subscription model.timeline AnimationTick
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
    , forKey "ArrowDown" |> fireMsg NextAction
    , forKey "ArrowUp" |> fireMsg PreviousAction
    , forKey "ArrowRight" |> fireMsg NextMove
    , forKey "ArrowLeft" |> fireMsg PreviousMove
    ]



-- VIEW


view : Shared.Model -> Model -> View Msg
view shared model =
    { title = "Watch Replay - pacoplay.com"
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
        RemoteData.NotAsked ->
            Pages.NotFound.body

        RemoteData.Loading ->
            Element.text "Loading replay data ..."

        RemoteData.Failure _ ->
            Pages.NotFound.body

        RemoteData.Success replay ->
            successBody shared model replay


successBody : Shared.Model -> Model -> Replay -> Element Msg
successBody shared model replay =
    el [ centerX, height fill, width (Element.maximum 1120 fill) ]
        (Element.row
            [ width fill, height fill, paddingXY 10 0, spacing 10 ]
            [ column [ width fill, height fill ] [ boardView model replay ]
            , sidebar shared model
            ]
        )



--------------------------------------------------------------------------------
-- Board View ------------------------------------------------------------------
--------------------------------------------------------------------------------


{-| Time to move from one board state to the next.
-}
motionTime : Animation.Duration
motionTime =
    Animation.milliseconds 200


{-| Pause between two actions in a chain.
-}
chainPauseTime : Animation.Duration
chainPauseTime =
    Animation.milliseconds 150


{-| Show the game state at `model.actionCount`.
-}
boardView : Model -> Replay -> Element Msg
boardView model replay =
    case currentBoard model replay of
        ReplayOk actions position ->
            Element.el
                [ width fill
                , height fill
                , Element.scrollbarY
                , centerX
                ]
                (boardViewOk model actions position)

        ReplayToShort ->
            Element.text "Replay is corrupted, too short :-("

        ReplayError ->
            Element.text "Replay is corrupted, rule violation :-("


{-| Given a model where the timeline does not match the actionCount, this adds
an animation to the timeline which transitions to the correct actionCount view.

While this is technically an update function, it is closely related to the board
view so I am putting it in this section.

-}
animateDirect : Model -> Model
animateDirect model =
    model.replay
        |> RemoteData.toMaybe
        |> Maybe.andThen (animateDirectR model)
        |> Maybe.map (\renderData -> { model | timeline = Animation.queue ( motionTime, renderData ) model.timeline })
        |> Maybe.withDefault model


animateDirectR : Model -> Replay -> Maybe OpaqueRenderData
animateDirectR model replay =
    let
        board =
            currentBoard model replay
    in
    case board of
        ReplayOk _ boardOk ->
            Just (PositionView.renderStatic Svg.WhiteBottom boardOk)

        ReplayToShort ->
            Nothing

        ReplayError ->
            Nothing


type BoardReplayState
    = ReplayOk (List Sako.Action) Sako.Position
    | ReplayToShort
    | ReplayError


currentBoard : Model -> Replay -> BoardReplayState
currentBoard model replay =
    let
        actions =
            List.take model.actionCount replay.actions
                |> List.map (\( action, _ ) -> action)
    in
    if List.length actions == model.actionCount then
        Sako.doActionsList actions Sako.initialPosition
            |> Maybe.map (ReplayOk actions)
            |> Maybe.withDefault ReplayError

    else
        ReplayToShort


boardViewOk : Model -> List Sako.Action -> Sako.Position -> Element Msg
boardViewOk model actions position =
    PositionView.viewTimeline
        { colorScheme =
            Colors.configToOptions Colors.defaultBoardColors
        , nodeId = Nothing
        , decoration = decoration model actions position
        , dragPieceData = []
        , mouseDown = Maybe.map MouseDown model.inputMode
        , mouseUp = Maybe.map MouseUp model.inputMode
        , mouseMove = Maybe.map MouseMove model.inputMode
        , additionalSvg = Nothing
        , replaceViewport =
            Just
                { x = -10
                , y = -80
                , width = 820
                , height = 960
                }
        }
        model.timeline


decoration : Model -> List Sako.Action -> Sako.Position -> List PositionView.BoardDecoration
decoration model actions position =
    if model.showMovementIndicators then
        CastingDeco.toDecoration PositionView.castingDecoMappers model.castingDeco
            ++ (PositionView.pastMovementIndicatorList position actions
                    |> List.map PositionView.PastMovementIndicator
               )

    else
        CastingDeco.toDecoration PositionView.castingDecoMappers model.castingDeco



--------------------------------------------------------------------------------
-- Sidebar ---------------------------------------------------------------------
--------------------------------------------------------------------------------


sidebar : Shared.Model -> Model -> Element Msg
sidebar shared model =
    Element.column [ spacing 10, padding 10, alignTop, height fill, width (px 250) ]
        [ Components.gameCodeLabel
            (CopyToClipboard (Url.toString shared.url))
            model.key
        , arrowButtons
        , Element.text "(or use arrow keys)"
        , enableMovementIndicators model.showMovementIndicators
        , editorLink model
        , rematchLink model
        , actionList model
        , CastingDeco.configView
            { setInputMode = SetInputMode
            , clearTiles = ClearDecoTiles
            , clearArrows = ClearDecoArrows
            }
            model.inputMode
            model.castingDeco
        ]


arrowButtons : Element Msg
arrowButtons =
    Element.row [ spacing 10 ]
        [ Components.iconButton "Previous move." Solid.arrowLeft (Just PreviousMove)
        , Components.iconButton "Previous action." Solid.chevronLeft (Just PreviousAction)
        , Components.iconButton "Play all." Solid.play (Just PlayAll)
        , Components.iconButton "Next action." Solid.chevronRight (Just NextAction)
        , Components.iconButton "Next move." Solid.arrowRight (Just NextMove)
        ]


enableMovementIndicators : Bool -> Element Msg
enableMovementIndicators showMovementIndicators =
    if showMovementIndicators then
        Element.none

    else
        Element.row [ spacing 10 ]
            [ Components.iconButton "" Solid.eye (Just EnableMovementIndicators)
            , Element.text "Show movement indicators"
            ]


editorLink : Model -> Element msg
editorLink model =
    Element.link [ Font.underline, Font.color (Element.rgb 0 0 1) ]
        { url = Route.toHref Route.Editor ++ "?game=" ++ model.key ++ "&action=" ++ String.fromInt model.actionCount
        , label = Element.text T.replayShowInEditor
        }


rematchLink : Model -> Element Msg
rematchLink model =
    Input.button [ Font.underline, Font.color (Element.rgb 0 0 1) ]
        { onPress = Just <| RematchFromActionIndex model.key model.actionCount
        , label = Element.text T.replayRematchFromHere
        }


{-| The interactive list of all action that happened in the game. You can click
on one action go to to that position.
-}
actionList : Model -> Element Msg
actionList model =
    Element.column [ width fill, height fill, scrollbarY ]
        (setupButton model :: List.map (sidebarMove model) model.sidebarData)


{-| Button that brings you to actionCount == 0, i.e. an inital board state.
-}
setupButton : Model -> Element Msg
setupButton model =
    let
        attrs =
            if model.actionCount == 0 then
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
        { onPress = Just (GoToActionCount 0)
        , label = Element.text "Restart"
        }


sidebarMove : Model -> Notation.SidebarMoveData -> Element Msg
sidebarMove model moveData =
    Element.row [ width fill, moveBackground moveData.color ]
        [ sidebarMoveComlete moveData
        , Element.wrappedRow [ width (fillPortion 4) ] (List.map (sidebarAction model) moveData.actions)
        ]


{-| Left side, summarizes all action of a move into a single block.
You can click this block to go to the end of the whole move block.
-}
sidebarMoveComlete : Notation.SidebarMoveData -> Element Msg
sidebarMoveComlete moveData =
    Input.button [ height fill, width (fillPortion 1), paddingXY 5 0 ]
        { onPress = goToLastAction moveData
        , label = Element.text (String.fromInt moveData.moveNumber)
        }


goToLastAction : Notation.SidebarMoveData -> Maybe Msg
goToLastAction moveData =
    moveData.actions
        |> List.last
        |> Maybe.map (\cak -> GoToActionCount cak.actionIndex)


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
sidebarAction : Model -> Notation.ConsensedActionKey -> Element Msg
sidebarAction model cak =
    let
        attrs =
            if model.actionCount == cak.actionIndex then
                [ Background.color (Element.rgb255 51 191 255), paddingXY 0 5 ]

            else
                [ paddingXY 0 5
                , Element.mouseOver [ Background.color (Element.rgb255 102 206 255) ]
                ]
    in
    Input.button attrs
        { onPress = Just (GoToActionCount cak.actionIndex)
        , label = Element.text (Notation.writeOut cak.actions)
        }
