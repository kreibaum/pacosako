module Pages.Replay.Id_String exposing (Model, Msg, Params, page)

{-| Watch replays of games that were played in /game/{id}
-}

import Api.Backend exposing (Replay)
import Components
import Element exposing (Element, alignTop, centerX, fill, fillPortion, height, padding, scrollbarY, spacing, width)
import Element.Background as Background
import Element.Input as Input
import Http
import List.Extra as List
import Pages.NotFound
import Pieces
import PositionView
import RemoteData exposing (WebData)
import Sako exposing (Action, Color(..))
import Shared
import Spa.Document exposing (Document)
import Spa.Page as Page exposing (Page)
import Spa.Url as Url exposing (Url)
import Svg.Custom as Svg


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
    { replay : WebData Replay
    , sidebarData : SidebarData
    , key : String
    , actionCount : Int
    }


init : Shared.Model -> Url Params -> ( Model, Cmd Msg )
init shared { params } =
    ( { replay = RemoteData.Loading
      , sidebarData = []
      , key = params.id
      , actionCount = 0
      }
    , Api.Backend.getReplay params.id HttpErrorReplay GotReplay
    )



-- UPDATE


type Msg
    = GotReplay Replay
    | HttpErrorReplay Http.Error
    | TriggerReplayReload
    | GoToActionCount Int


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotReplay replay ->
            ( { model
                | replay = RemoteData.Success replay
                , sidebarData = sidebarData replay
              }
            , Cmd.none
            )

        HttpErrorReplay error ->
            ( { model | replay = RemoteData.Failure error }, Cmd.none )

        TriggerReplayReload ->
            ( { model | replay = RemoteData.Loading }
            , Api.Backend.getReplay model.key HttpErrorReplay GotReplay
            )

        GoToActionCount actionCount ->
            ( { model | actionCount = actionCount }, Cmd.none )


save : Model -> Shared.Model -> Shared.Model
save model shared =
    shared


load : Shared.Model -> Model -> ( Model, Cmd Msg )
load shared model =
    ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none



-- VIEW


view : Model -> Document Msg
view model =
    { title = "Watch Replay - pacoplay.com"
    , body = [ body model ]
    }



-- Constants


bg =
    { black = Element.rgb255 200 200 200
    , white = Element.rgb255 240 240 240
    , selected = Element.rgb255 220 255 220
    }


body : Model -> Element Msg
body model =
    case model.replay of
        RemoteData.NotAsked ->
            Pages.NotFound.body

        RemoteData.Loading ->
            Element.text "Loading replay data ..."

        RemoteData.Failure e ->
            Pages.NotFound.body

        RemoteData.Success replay ->
            successBody model replay


successBody : Model -> Replay -> Element Msg
successBody model replay =
    Element.row
        [ width fill, height fill, Element.scrollbarY ]
        [ boardView model replay
        , sidebar model replay
        ]



--------------------------------------------------------------------------------
-- Board View ------------------------------------------------------------------
--------------------------------------------------------------------------------


{-| Show the game state at `model.actionCount`.
-}
boardView : Model -> Replay -> Element Msg
boardView model replay =
    Element.el [ width (fillPortion 3), height fill ]
        (case currentBoard model replay of
            ReplayOk actions position ->
                boardViewOk actions position

            ReplayToShort ->
                Element.text "Replay is corrupted, too short :-("

            ReplayError ->
                Element.text "Replay is corrupted, rule violation :-("
        )


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


boardViewOk : List Sako.Action -> Sako.Position -> Element msg
boardViewOk actions position =
    PositionView.renderStatic Svg.WhiteBottom position
        |> PositionView.viewStatic
            { colorScheme = Pieces.defaultColorScheme
            , nodeId = Nothing
            , decoration = decoration actions position
            , dragPieceData = []
            , mouseDown = Nothing
            , mouseUp = Nothing
            , mouseMove = Nothing
            , additionalSvg = Nothing
            , replaceViewport = Nothing
            }


decoration : List Sako.Action -> Sako.Position -> List PositionView.BoardDecoration
decoration actions position =
    --playViewHighlight play
    --  ++ CastingDeco.toDecoration castingDecoMappers play.castingDeco
    PositionView.pastMovementIndicatorList position actions
        |> List.map PositionView.PastMovementIndicator



--------------------------------------------------------------------------------
-- Sidebar ---------------------------------------------------------------------
--------------------------------------------------------------------------------


sidebar : Model -> Replay -> Element Msg
sidebar model replay =
    Element.column [ spacing 10, padding 10, alignTop, height fill, width (fillPortion 1) ]
        [ Components.gameIdBadgeBig model.key
        , Element.text "[timer info]"
        , Element.text "[|<<] [<] [>] [>>|]"
        , actionList model replay
        , Element.text "[Result]"
        ]


{-| The interactive list of all action that happened in the game. You can click
on one action go to to that position.
-}
actionList : Model -> Replay -> Element Msg
actionList model replay =
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
        , Element.column [ width (fillPortion 4) ] (List.map (sidebarAction model) moveData.actions)
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
            [ Just (padding 5)
            , Just (width fill)
            , if model.actionCount == count then
                Just (Background.color (Element.rgb255 220 255 220))

              else
                Nothing
            ]
                |> List.filterMap (\e -> e)
    in
    Input.button attrs
        { onPress = Just (GoToActionCount count)
        , label = Element.text (actionText action)
        }


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
