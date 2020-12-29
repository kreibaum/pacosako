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
import Components
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
import I18n.Strings as I18n exposing (I18nToken(..), Language(..), t)
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
    { title = "Paco Ŝako - pacoplay.com"
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



--------------------------------------------------------------------------------
-- View code -------------------------------------------------------------------
--------------------------------------------------------------------------------


matchSetupUi : Model -> Element Msg
matchSetupUi model =
    Element.column [ width fill, height fill, scrollbarY ]
        [ Components.header1 (t model.language i18nPlayPacoSako)
        , matchSetupUiInner model
        ]


matchSetupUiInner : Model -> Element Msg
matchSetupUiInner model =
    Element.column [ width (fill |> Element.maximum 1200), padding 5, spacing 5, centerX ]
        [ Element.row [ width fill, spacing 5, centerX ]
            [ joinOnlineMatchUi model
            , setupOnlineMatchUi model
            ]
        , recentGamesList model model.recentGames
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
        [ Element.el [ centerX, Font.size 30 ] (Element.text (t model.language i18nCreateNewGame))
        , Element.row [ width fill, spacing 7 ]
            [ speedButton
                { buttonIcon = Solid.spaceShuttle
                , caption = t model.language i18nLightspeed
                , event = SetTimeLimit 180
                , selected = model.timeLimit == 180
                }
            , speedButton
                { buttonIcon = Solid.bolt
                , caption = t model.language i18nBlitz
                , event = SetTimeLimit 300
                , selected = model.timeLimit == 300
                }
            ]
        , Element.row [ width fill, spacing 7 ]
            [ speedButton
                { buttonIcon = Solid.frog
                , caption = t model.language i18nRapid
                , event = SetTimeLimit 600
                , selected = model.timeLimit == 600
                }
            , speedButton
                { buttonIcon = Solid.couch
                , caption = t model.language i18nRelaxed
                , event = SetTimeLimit 1200
                , selected = model.timeLimit == 1200
                }
            ]
        , Element.row [ width fill, spacing 7 ]
            [ speedButton
                { buttonIcon = Solid.wrench
                , caption = t model.language i18nCustom
                , event = SetTimeLimit model.timeLimit
                , selected = List.notMember model.timeLimit [ 0, 180, 300, 600, 1200 ]
                }
            , speedButton
                { buttonIcon = Solid.dove
                , caption = t model.language i18nNoTimer
                , event = SetTimeLimit 0
                , selected = model.timeLimit == 0
                }
            ]
        , Input.text []
            { onChange = SetRawTimeLimit
            , text = model.rawTimeLimit
            , placeholder = Nothing
            , label = Input.labelLeft [ centerY ] (Element.text (t model.language i18nTimeInSeconds))
            }
        , timeLimitLabel model model.timeLimit
        , bigRoundedButton (Element.rgb255 200 210 200)
            (Just CreateMatch)
            [ Element.text (t model.language i18nCreateMatch) ]
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
timeLimitLabel : Model -> Int -> Element msg
timeLimitLabel model seconds =
    let
        data =
            distributeSeconds seconds
    in
    if seconds > 0 then
        t model.language i18nMinutesAndSeconds data
            |> Element.text

    else
        Element.text (t model.language i18nPlayWithoutTimeLimit)


distributeSeconds : Int -> { seconds : Int, minutes : Int }
distributeSeconds seconds =
    { seconds = seconds |> modBy 60, minutes = seconds // 60 }


joinOnlineMatchUi : Model -> Element Msg
joinOnlineMatchUi model =
    box (Element.rgb255 220 220 230)
        [ Element.el [ centerX, Font.size 30 ] (Element.text (t model.language i18nIGotAnInvite))
        , Input.text [ width fill, onKeyUpAttr [ forKey "Enter" |> fireMsg JoinMatch ] ]
            { onChange = SetRawMatchId
            , text = model.rawMatchId
            , placeholder = Just (Input.placeholder [] (Element.text (t model.language i18nEnterMatchId)))
            , label = Input.labelLeft [ centerY ] (Element.text (t model.language i18nMatchId))
            }
        , bigRoundedButton (Element.rgb255 200 200 210)
            (Just JoinMatch)
            [ Element.text (t model.language i18nJoinGame) ]
        ]


{-| A button that is implemented via a vertical column.
-}
bigRoundedButton : Element.Color -> Maybe msg -> List (Element msg) -> Element msg
bigRoundedButton color event content =
    Input.button [ Background.color color, width fill, height fill, Border.rounded 5 ]
        { onPress = event
        , label = Element.column [ height fill, centerX, padding 15, spacing 10 ] content
        }


recentGamesList : Model -> WebData (List String) -> Element Msg
recentGamesList model data =
    case data of
        RemoteData.NotAsked ->
            Input.button [ padding 10 ]
                { onPress = Just RefreshRecentGames
                , label = Element.text (t model.language i18nRecentSearchNotAsked)
                }

        RemoteData.Loading ->
            Element.el [ padding 10 ]
                (Element.text (t model.language i18nRecentSearchLoading))

        RemoteData.Failure _ ->
            Input.button [ padding 10 ]
                { onPress = Just RefreshRecentGames
                , label = Element.text (t model.language i18nRecentSearchError)
                }

        RemoteData.Success games ->
            recentGamesListSuccess model games


recentGamesListSuccess : Model -> List String -> Element Msg
recentGamesListSuccess model games =
    if List.isEmpty games then
        Input.button [ padding 10 ]
            { onPress = Just RefreshRecentGames
            , label = Element.text (t model.language i18nRecentSearchNoGames)
            }

    else
        Element.row [ width fill, spacing 5 ]
            (List.map recentGamesListSuccessOne games
                ++ [ Input.button
                        [ padding 10
                        , Background.color (Element.rgb 0.9 0.9 0.9)
                        ]
                        { onPress = Just RefreshRecentGames
                        , label = Element.text (t model.language i18nRecentSearchRefresh)
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



--------------------------------------------------------------------------------
-- I18n Strings ----------------------------------------------------------------
--------------------------------------------------------------------------------


i18nPlayPacoSako : I18nToken String
i18nPlayPacoSako =
    I18nToken
        { english = "Play Paco Ŝako"
        , dutch = "Speel Paco Ŝako"
        , esperanto = "Ludi Paco Ŝakon"
        }


i18nCreateNewGame : I18nToken String
i18nCreateNewGame =
    I18nToken
        { english = "Create a new Game"
        , dutch = "Maak een nieuw spel"
        , esperanto = "Kreu novan ludon"
        }


i18nLightspeed : I18nToken String
i18nLightspeed =
    I18nToken
        { english = "Lightspeed"
        , dutch = "Lichtsnelheid"
        , esperanto = "Lumrapideco"
        }


i18nBlitz : I18nToken String
i18nBlitz =
    I18nToken
        { english = "Blitz"
        , dutch = "Blitz"
        , esperanto = "Fulmo"
        }


i18nRapid : I18nToken String
i18nRapid =
    I18nToken
        { english = "Rapid"
        , dutch = "Snel"
        , esperanto = "Rapida"
        }


i18nRelaxed : I18nToken String
i18nRelaxed =
    I18nToken
        { english = "Relaxed"
        , dutch = "Ontspannen"
        , esperanto = "Malstreĉita"
        }


i18nCustom : I18nToken String
i18nCustom =
    I18nToken
        { english = "Custom"
        , dutch = "Op maat"
        , esperanto = "Propra"
        }


i18nNoTimer : I18nToken String
i18nNoTimer =
    I18nToken
        { english = "No Timer"
        , dutch = "Geen timer"
        , esperanto = "Sen Tempigilo"
        }


i18nTimeInSeconds : I18nToken String
i18nTimeInSeconds =
    I18nToken
        { english = "Time in seconds"
        , dutch = "Tijd in seconden"
        , esperanto = "Tempo en sekundoj"
        }


i18nCreateMatch : I18nToken String
i18nCreateMatch =
    I18nToken
        { english = "Create Match"
        , dutch = "Partij maken"
        , esperanto = "Krei Matĉon"
        }


i18nMinutesAndSeconds : I18nToken ({ seconds : Int, minutes : Int } -> String)
i18nMinutesAndSeconds =
    I18nToken
        { english =
            \data ->
                String.fromInt data.minutes
                    ++ " Minutes and "
                    ++ String.fromInt data.seconds
                    ++ " Seconds for each player"
        , dutch =
            \data ->
                String.fromInt data.minutes
                    ++ " minuten en "
                    ++ String.fromInt data.seconds
                    ++ " seconden voor elke speler"
        , esperanto =
            \data ->
                String.fromInt data.minutes
                    ++ " Minutoj kaj "
                    ++ String.fromInt data.seconds
                    ++ " Sekundoj por ĉiu ludanto"
        }


i18nPlayWithoutTimeLimit : I18nToken String
i18nPlayWithoutTimeLimit =
    I18nToken
        { english = "Play without time limit"
        , dutch = "Speel zonder tijdslimiet"
        , esperanto = "Ludi sen tempolimo"
        }


i18nIGotAnInvite : I18nToken String
i18nIGotAnInvite =
    I18nToken
        { english = "I got an invite"
        , dutch = "Ik heb een uitnodiging"
        , esperanto = "Mi ricevis inviton"
        }


i18nEnterMatchId : I18nToken String
i18nEnterMatchId =
    I18nToken
        { english = "Enter Match Id"
        , dutch = "Geef overeenkomst-ID op"
        , esperanto = "Enigu Matĉan Identigilon"
        }


i18nMatchId : I18nToken String
i18nMatchId =
    I18nToken
        { english = "Match Id"
        , dutch = "Overeenkomst-ID"
        , esperanto = "Matĉa identigilo"
        }


i18nJoinGame : I18nToken String
i18nJoinGame =
    I18nToken
        { english = "Join Game"
        , dutch = "Speel mee"
        , esperanto = "Aliĝi al Ludo"
        }


i18nRecentSearchNotAsked : I18nToken String
i18nRecentSearchNotAsked =
    I18nToken
        { english = "Search for recent games"
        , dutch = "Zoeken naar recente games"
        , esperanto = "Serĉi lastatempajn ludojn"
        }


i18nRecentSearchLoading : I18nToken String
i18nRecentSearchLoading =
    I18nToken
        { english = "Searching for recent games..."
        , dutch = "Zoeken naar recente games ..."
        , esperanto = "Serĉante lastatempajn ludojn ..."
        }


i18nRecentSearchError : I18nToken String
i18nRecentSearchError =
    I18nToken
        { english = "Error while searching for games! Try again?"
        , dutch = "Fout bij het zoeken naar games! Opnieuw proberen?"
        , esperanto = "Eraro dum serĉado de ludoj! Ĉu provi denove?"
        }


i18nRecentSearchNoGames : I18nToken String
i18nRecentSearchNoGames =
    I18nToken
        { english = "There were no games recently started. Check again?"
        , dutch = "Er zijn onlangs geen games gestart. Nogmaals controleren?"
        , esperanto = "Lastatempe neniuj ludoj komenciĝis. Ĉu denove kontroli?"
        }


i18nRecentSearchRefresh : I18nToken String
i18nRecentSearchRefresh =
    I18nToken
        { english = "Refresh"
        , dutch = "Vernieuwen"
        , esperanto = "Refreŝigi"
        }
