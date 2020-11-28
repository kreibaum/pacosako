module Pages.Top exposing (Model, Msg, Params, page)

import Animation exposing (Timeline)
import Api.Ai
import Api.Backend
import Api.Ports as Ports
import Api.Websocket as Websocket exposing (CurrentMatchState)
import Arrow exposing (Arrow)
import Browser
import Browser.Events
import Browser.Navigation exposing (pushUrl)
import CastingDeco
import Custom.Element exposing (icon)
import Custom.Events exposing (BoardMousePosition, fireMsg, forKey, onKeyUpAttr)
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
import Spa.Page as Page
import Spa.Url exposing (Url)
import Svg exposing (Svg)
import Svg.Attributes as SvgA
import Svg.Custom as Svg exposing (BoardRotation(..))
import Time exposing (Posix)
import Timer


type alias Params =
    ()


page : Page.Page Params Model Msg
page =
    Page.application
        { init = \shared params -> init shared
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        , save = save
        , load = load
        }


view : Model -> Document Msg
view model =
    { title = "Paco Ŝako"
    , body = [ matchSetupUi model ]
    }


save : Model -> Shared.Model -> Shared.Model
save model shared =
    { shared | user = model.login }


load : Shared.Model -> Model -> ( Model, Cmd Msg )
load shared model =
    ( { model
        | login = shared.user
        , language = shared.language
      }
    , refreshRecentGames
    )


type alias User =
    { id : Int
    , username : String
    }


init : Shared.Model -> ( Model, Cmd Msg )
init shared =
    ( { rawMatchId = ""
      , matchConnectionStatus = NoMatchConnection
      , timeLimit = 300
      , rawTimeLimit = "300"
      , recentGames = RemoteData.Loading
      , key = shared.key
      , login = shared.user
      , language = shared.language
      }
    , refreshRecentGames
    )



--------------------------------------------------------------------------------
-- View code -------------------------------------------------------------------
--------------------------------------------------------------------------------


distributeSeconds : Int -> { seconds : Int, minutes : Int }
distributeSeconds seconds =
    { seconds = seconds |> modBy 60, minutes = seconds // 60 }


type Msg
    = SetRawMatchId String
    | JoinMatch
    | CreateMatch
    | MatchCreatedOnServer String
    | SetTimeLimit Int
    | SetRawTimeLimit String
    | RefreshRecentGames
    | GotRecentGames (List String)
    | ErrorRecentGames Http.Error
    | HttpError Http.Error


type alias Model =
    { rawMatchId : String
    , matchConnectionStatus : MatchConnectionStatus
    , timeLimit : Int
    , rawTimeLimit : String
    , recentGames : WebData (List String)
    , key : Browser.Navigation.Key
    , language : Language
    , login : Maybe User
    }


type MatchConnectionStatus
    = NoMatchConnection
    | MatchConnectionRequested String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
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

        HttpError error ->
            ( model, Ports.logToConsole (Api.Backend.describeError error) )


refreshRecentGames : Cmd Msg
refreshRecentGames =
    Api.Backend.getRecentGameKeys ErrorRecentGames GotRecentGames


{-| Parse the rawTimeLimit into an integer and take it over to the time limit if
parsing is successfull.
-}
tryParseRawLimit : Model -> Model
tryParseRawLimit model =
    case String.toInt model.rawTimeLimit of
        Just newLimit ->
            { model | timeLimit = newLimit }

        Nothing ->
            model


joinMatch : Model -> ( Model, Cmd Msg )
joinMatch model =
    ( { model | matchConnectionStatus = MatchConnectionRequested model.rawMatchId }
    , pushUrl model.key (Route.toString (Route.Game__Id_String { id = model.rawMatchId }))
    )


{-| Requests a new syncronized match from the server.
-}
createMatch : Model -> ( Model, Cmd Msg )
createMatch model =
    let
        timerConfig =
            if model.timeLimit > 0 then
                Just (Timer.secondsConfig { white = model.timeLimit, black = model.timeLimit })

            else
                Nothing
    in
    ( model, Api.Backend.postMatchRequest timerConfig HttpError MatchCreatedOnServer )


matchSetupUi : Model -> Element Msg
matchSetupUi model =
    Element.column [ width fill, height fill, scrollbarY ]
        [ Element.el [ padding 40, centerX, Font.size 40 ] (Element.text "Play Paco Ŝako")
        , matchSetupUiInner model
        ]


matchSetupUiInner : Model -> Element Msg
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


setupOnlineMatchUi : Model -> Element Msg
setupOnlineMatchUi model =
    box (Element.rgb255 220 230 220)
        [ Element.el [ centerX, Font.size 30 ] (Element.text "Create a new Game")
        , Element.row [ width fill, spacing 7 ]
            [ speedButton
                { buttonIcon = Solid.spaceShuttle
                , caption = "Lightspeed"
                , event = SetTimeLimit 180
                , selected = model.timeLimit == 180
                }
            , speedButton
                { buttonIcon = Solid.bolt
                , caption = "Blitz"
                , event = SetTimeLimit 300
                , selected = model.timeLimit == 300
                }
            ]
        , Element.row [ width fill, spacing 7 ]
            [ speedButton
                { buttonIcon = Solid.frog
                , caption = "Rapid"
                , event = SetTimeLimit 600
                , selected = model.timeLimit == 600
                }
            , speedButton
                { buttonIcon = Solid.couch
                , caption = "Relaxed"
                , event = SetTimeLimit 1200
                , selected = model.timeLimit == 1200
                }
            ]
        , Element.row [ width fill, spacing 7 ]
            [ speedButton
                { buttonIcon = Solid.wrench
                , caption = "Custom"
                , event = SetTimeLimit model.timeLimit
                , selected = List.notMember model.timeLimit [ 0, 180, 300, 600, 1200 ]
                }
            , speedButton
                { buttonIcon = Solid.dove
                , caption = "No Timer"
                , event = SetTimeLimit 0
                , selected = model.timeLimit == 0
                }
            ]
        , Input.text []
            { onChange = SetRawTimeLimit
            , text = model.rawTimeLimit
            , placeholder = Nothing
            , label = Input.labelLeft [ centerY ] (Element.text "Time in seconds")
            }
        , timeLimitLabel model.timeLimit
        , bigRoundedButton (Element.rgb255 200 210 200)
            (Just CreateMatch)
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


joinOnlineMatchUi : Model -> Element Msg
joinOnlineMatchUi model =
    box (Element.rgb255 220 220 230)
        [ Element.el [ centerX, Font.size 30 ] (Element.text "I got an Invite")
        , Input.text [ width fill, onKeyUpAttr [ forKey "Enter" |> fireMsg JoinMatch ] ]
            { onChange = SetRawMatchId
            , text = model.rawMatchId
            , placeholder = Just (Input.placeholder [] (Element.text "Enter Match Id"))
            , label = Input.labelLeft [ centerY ] (Element.text "Match Id")
            }
        , bigRoundedButton (Element.rgb255 200 200 210)
            (Just JoinMatch)
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
                { onPress = Just RefreshRecentGames
                , label = Element.text "Search for recent games"
                }

        RemoteData.Loading ->
            Element.el [ padding 10 ]
                (Element.text "Searching for recent games...")

        RemoteData.Failure _ ->
            Input.button [ padding 10 ]
                { onPress = Just RefreshRecentGames
                , label = Element.text "Error while searching for games! Try again?"
                }

        RemoteData.Success games ->
            recentGamesListSuccess games


recentGamesListSuccess : List String -> Element Msg
recentGamesListSuccess games =
    if List.isEmpty games then
        Input.button [ padding 10 ]
            { onPress = Just RefreshRecentGames
            , label = Element.text "There were no games recently started. Check again?"
            }

    else
        Element.row [ width fill, spacing 5 ]
            (List.map recentGamesListSuccessOne games
                ++ [ Input.button
                        [ padding 10
                        , Background.color (Element.rgb 0.9 0.9 0.9)
                        ]
                        { onPress = Just RefreshRecentGames
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
        { onPress = Just (SetRawMatchId game)
        , label = Element.text game
        }
