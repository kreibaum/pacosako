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
import Effect exposing (Effect)
import Element exposing (Element, alignTop, centerX, column, el, fill, fillPortion, height, padding, paddingXY, px, scrollbarY, spacing, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import FontAwesome.Solid as Solid
import Gen.Route as Route
import Header
import Http
import List.Extra as List
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
    , sidebarData : SidebarData
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
                , sidebarData = sidebarData replay
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
                |> animateStepByStep (lastMove model)
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

-}
setAndAnimateActionCount : Int -> Model -> Model
setAndAnimateActionCount actionCount model =
    let
        firstNewActionCount =
            model.sidebarData
                -- find Move
                |> List.find (\move -> lastActionCountOf move >= actionCount)
                -- find first action of move
                |> Maybe.map .actions
                |> Maybe.andThen List.head
                -- extract corresponding action count
                |> Maybe.map (\( i, _ ) -> i)
                |> Maybe.withDefault actionCount
    in
    if actionCount > model.actionCount && model.actionCount + 1 == firstNewActionCount then
        -- Skip the "Lift" action that is at the start of moves.
        animateStepByStep actionCount { model | actionCount = model.actionCount + 1 }

    else if actionCount > model.actionCount && model.actionCount + 1 >= firstNewActionCount then
        animateStepByStep actionCount model

    else
        animateDirect { model | actionCount = actionCount }


{-| Tail recursive animation function that steps the timeline forward step by step.
-}
animateStepByStep : Int -> Model -> Model
animateStepByStep actionCount model =
    if model.actionCount >= actionCount then
        model

    else
        animateDirect { model | actionCount = model.actionCount + 1 }
            |> (\m -> { m | timeline = Animation.pause chainPauseTime m.timeline })
            |> animateStepByStep actionCount


{-| Just increases the actionCount by one and makes sure not to go above the
limit.
-}
nextAction : Model -> Int
nextAction model =
    let
        maxActionCount =
            model.sidebarData
                |> List.map (.actions >> List.length)
                |> List.sum
    in
    min (model.actionCount + 1) maxActionCount


{-| Just decreases the actionCount by one and makes sure it does not go below
zero.
-}
previousAction : Model -> Int
previousAction model =
    max (model.actionCount - 1) 0


{-| Finds the first move that is not already completely shown by the current
actionCount and then goes to the last action of this move.
-}
nextMove : Model -> Int
nextMove model =
    let
        actionCount =
            model.sidebarData
                |> List.find (\move -> lastActionCountOf move > model.actionCount)
                |> Maybe.map lastActionCountOf
                |> Maybe.withDefault model.actionCount
    in
    actionCount


{-| Given a move, returns the action count of the last action in in. If the
move is invalid (i.e. has no actions) then -42 is returned instead.
-}
lastActionCountOf : SidebarMoveData -> Int
lastActionCountOf data =
    List.last data.actions
        |> Maybe.map (\( i, _ ) -> i)
        |> Maybe.withDefault -42


{-| Given a move, returns the action count of the first action in in. If the
move is invalid (i.e. has no actions) then -42 is returned instead.
-}
firstActionCountOf : SidebarMoveData -> Int
firstActionCountOf data =
    List.head data.actions
        |> Maybe.map (\( i, _ ) -> i)
        |> Maybe.withDefault -42


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
                |> List.find (\move -> lastActionCountOf move >= model.actionCount)
                |> Maybe.map (\move -> firstActionCountOf move - 1)
                |> Maybe.withDefault 0
    in
    actionCount


lastMove : Model -> Int
lastMove model =
    let
        actionCount =
            model.sidebarData
                |> List.map (.actions >> List.length)
                |> List.sum
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
sidebar _ model =
    Element.column [ spacing 10, padding 10, alignTop, height fill, width (px 250) ]
        [ Components.gameIdBadgeBig model.key
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
        background =
            if model.actionCount == 0 then
                Background.color bg.selected

            else
                Background.color bg.black
    in
    Input.button [ padding 5, background, width fill ]
        { onPress = Just (GoToActionCount 0)
        , label = Element.text "Restart"
        }


sidebarMove : Model -> SidebarMoveData -> Element Msg
sidebarMove model moveData =
    Element.row [ width fill, moveBackground moveData.color ]
        [ sidebarMoveComlete moveData
        , Element.wrappedRow [ width (fillPortion 4) ] (List.map (sidebarAction model) moveData.actions)
        ]


{-| Left side, summarizes all action of a move into a single block.
You can click this block to go to the end of the whole move block.
-}
sidebarMoveComlete : SidebarMoveData -> Element Msg
sidebarMoveComlete moveData =
    Input.button [ height fill, width (fillPortion 1), padding 5 ]
        { onPress = goToLastAction moveData
        , label = Element.text (String.fromInt moveData.moveNumber)
        }


goToLastAction : SidebarMoveData -> Maybe Msg
goToLastAction moveData =
    moveData.actions
        |> List.last
        |> Maybe.map (\( count, _ ) -> GoToActionCount count)


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
sidebarAction : Model -> ( Int, Sako.Action ) -> Element Msg
sidebarAction model ( count, action ) =
    let
        attrs =
            [ Just (padding 3)
            , Just (Border.rounded 4)
            , Just (Border.color (Element.rgb 0 0 0))
            , Just (Border.width 1)
            , if model.actionCount == count then
                Just (Background.color (Element.rgb255 220 255 220))

              else
                Nothing
            ]
                |> List.filterMap (\e -> e)
    in
    Element.el [ padding 2 ]
        (Input.button attrs
            { onPress = Just (GoToActionCount count)
            , label = Element.text (actionText action)
            }
        )


{-| Human readable form of the action for display.
-}
actionText : Sako.Action -> String
actionText action =
    case action of
        Sako.Lift tile ->
            "Lift " ++ Sako.tileToIdentifier tile

        Sako.Place tile ->
            "Place " ++ Sako.tileToIdentifier tile

        Sako.Promote pieceType ->
            "Promote " ++ Sako.toStringType pieceType


type alias SidebarData =
    List SidebarMoveData


type alias SidebarMoveData =
    { moveNumber : Int
    , color : Sako.Color
    , actions : List ( Int, Sako.Action )
    }


{-| Takes a replay and prepares the data for the sidebar. This would usually be
quite a stateful computation, so in elm we are folding with quite a bit of
carry over information.
-}
sidebarData : Replay -> SidebarData
sidebarData replay =
    replay.actions
        |> List.indexedMap (\i ( action, _ ) -> ( i + 1, action ))
        |> breakAt (\( _, action ) -> isLift action)
        |> List.indexedMap
            (\i actions ->
                { moveNumber = i // 2 + 1
                , color =
                    if modBy 2 i == 0 then
                        White

                    else
                        Black
                , actions = actions
                }
            )


{-| Separates a list into sublist where a new list is started whenever the
predicate is true.

    breakAt id [ True, False, True ]
        == [ [ True, False ], [ True ] ]

    breakAt id [ False, False, True, True, False, True, False ]
        == [ [ False, False ], [ True ], [ True, False ], [ True, False ] ]

-}
breakAt : (a -> Bool) -> List a -> List (List a)
breakAt p list =
    case list of
        [] ->
            []

        x :: xs ->
            breakAtInner p xs ( [ x ], [] )
                |> (\( _, accOuter ) -> List.reverse accOuter)


breakAtInner : (a -> Bool) -> List a -> ( List a, List (List a) ) -> ( List a, List (List a) )
breakAtInner p list ( accInner, accOuter ) =
    case list of
        [] ->
            ( [], List.reverse accInner :: accOuter )

        x :: xs ->
            if p x then
                breakAtInner p xs ( [ x ], List.reverse accInner :: accOuter )

            else
                breakAtInner p xs ( x :: accInner, accOuter )


isLift : Sako.Action -> Bool
isLift action =
    case action of
        Sako.Lift _ ->
            True

        _ ->
            False
