module Pages.Home_ exposing (Model, Msg, Params, page)

import Api.Backend
import Api.Decoders exposing (CurrentMatchState)
import Api.Ports as Ports
import Browser.Navigation exposing (pushUrl)
import Components
import Custom.Element exposing (icon)
import Custom.Events exposing (fireMsg, forKey, onKeyUpAttr)
import Effect exposing (Effect)
import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Element.Lazy exposing (lazy2)
import FontAwesome.Icon exposing (Icon)
import FontAwesome.Solid as Solid
import Gen.Route as Route
import Header
import Http
import I18n.Strings exposing (I18nToken(..), Language, t)
import Page
import PositionView exposing (BoardDecoration(..), DraggingPieces(..), Highlight(..))
import RemoteData exposing (WebData)
import Request
import Sako exposing (Tile(..))
import Shared
import Svg.Custom exposing (BoardRotation(..))
import Timer
import View exposing (View)


type alias Params =
    ()


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared _ =
    Page.advanced
        { init = init shared
        , update = update
        , view = view shared
        , subscriptions = \_ -> Sub.none
        }


view : Shared.Model -> Model -> View Msg
view shared model =
    { title = "Paco Ŝako - pacoplay.com"
    , element =
        Header.wrapWithHeader shared ToShared (matchSetupUi shared model)
    }


type alias User =
    { id : Int
    , username : String
    }


init : Shared.Model -> ( Model, Effect Msg )
init shared =
    ( { rawMatchId = ""
      , matchConnectionStatus = NoMatchConnection
      , speedSetting = Blitz
      , rawMinutes = ""
      , rawSeconds = ""
      , rawIncrement = ""
      , recentGames = RemoteData.Loading
      , key = shared.key
      , login = shared.user
      }
    , refreshRecentGames |> Effect.fromCmd
    )


type Msg
    = SetRawMatchId String
    | JoinMatch
    | CreateMatch
    | MatchCreatedOnServer String
    | SetSpeedSetting SpeedSetting
    | SetRawMinutes String
    | SetRawSeconds String
    | SetRawIncrement String
    | RefreshRecentGames
    | GotRecentGames (List CurrentMatchState)
    | ErrorRecentGames Http.Error
    | HttpError Http.Error
    | ToShared Shared.Msg


type alias Model =
    { rawMatchId : String
    , matchConnectionStatus : MatchConnectionStatus
    , speedSetting : SpeedSetting
    , rawMinutes : String
    , rawSeconds : String
    , rawIncrement : String
    , recentGames : WebData (List CurrentMatchState)
    , key : Browser.Navigation.Key
    , login : Maybe User
    }


{-| Enum that encapsulates all speed presets as well as the custom speed setting.
-}
type SpeedSetting
    = Lightspeed
    | Blitz
    | Rapid
    | Relaxed
    | Custom { minutes : Int, seconds : Int, increment : Int }
    | NoTimer


type alias CustomSpeedSetting =
    { minutes : Int, seconds : Int, increment : Int }


defaultCustom : CustomSpeedSetting
defaultCustom =
    { minutes = 4, seconds = 0, increment = 5 }


isCustom : SpeedSetting -> Bool
isCustom selection =
    case selection of
        Custom _ ->
            True

        _ ->
            False


{-| When switching over to "Custom", we need to transform the current selection
into values. We also need this to show the player what they have selected.
-}
intoCustomSpeedSetting : SpeedSetting -> Maybe CustomSpeedSetting
intoCustomSpeedSetting selection =
    case selection of
        Lightspeed ->
            Just <| CustomSpeedSetting 1 0 10

        Blitz ->
            Just <| CustomSpeedSetting 4 0 5

        Rapid ->
            Just <| CustomSpeedSetting 10 0 10

        Relaxed ->
            Just <| CustomSpeedSetting 20 0 10

        Custom { minutes, seconds, increment } ->
            Just <| CustomSpeedSetting minutes seconds increment

        NoTimer ->
            Nothing


buildTimerConfig : SpeedSetting -> Maybe Timer.TimerConfig
buildTimerConfig selection =
    let
        minSecSum min sec =
            60 * min + sec
    in
    intoCustomSpeedSetting selection
        |> Maybe.map
            (\{ minutes, seconds, increment } ->
                Timer.secondsConfig
                    { white = minSecSum minutes seconds
                    , black = minSecSum minutes seconds
                    , increment =
                        if increment > 0 then
                            Just increment

                        else
                            Maybe.Nothing
                    }
            )


type MatchConnectionStatus
    = NoMatchConnection
    | MatchConnectionRequested String


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        SetRawMatchId rawMatchId ->
            ( { model | rawMatchId = rawMatchId }, Effect.none )

        JoinMatch ->
            joinMatch model

        CreateMatch ->
            createMatch model

        MatchCreatedOnServer newId ->
            joinMatch { model | rawMatchId = newId }

        SetSpeedSetting newSetting ->
            ( { model | speedSetting = newSetting } |> setRawLimit, Effect.none )

        SetRawMinutes newRawMinutes ->
            ( { model | rawMinutes = newRawMinutes } |> tryParseRawLimit, Effect.none )

        SetRawSeconds newRawSeconds ->
            ( { model | rawSeconds = newRawSeconds } |> tryParseRawLimit, Effect.none )

        SetRawIncrement newRawIncrement ->
            ( { model | rawIncrement = newRawIncrement } |> tryParseRawLimit, Effect.none )

        GotRecentGames games ->
            ( { model | recentGames = RemoteData.Success (List.reverse games) }, Effect.none )

        ErrorRecentGames error ->
            ( { model | recentGames = RemoteData.Failure error }, Effect.none )

        RefreshRecentGames ->
            ( { model | recentGames = RemoteData.Loading }, refreshRecentGames |> Effect.fromCmd )

        HttpError error ->
            ( model, Ports.logToConsole (Api.Backend.describeError error) |> Effect.fromCmd )

        ToShared outMsg ->
            ( model, Effect.fromShared outMsg )


refreshRecentGames : Cmd Msg
refreshRecentGames =
    Api.Backend.getRecentGameKeys ErrorRecentGames GotRecentGames


{-| Parse the rawTimeLimit into an integer and take it over to the time limit if
parsing is successfull.
-}
tryParseRawLimit : Model -> Model
tryParseRawLimit model =
    case model.speedSetting of
        Custom { minutes, seconds, increment } ->
            { model
                | speedSetting =
                    Custom
                        { minutes = String.toInt model.rawMinutes |> Maybe.withDefault minutes
                        , seconds = String.toInt model.rawSeconds |> Maybe.withDefault seconds
                        , increment = String.toInt model.rawIncrement |> Maybe.withDefault increment
                        }
            }

        _ ->
            model


setRawLimit : Model -> Model
setRawLimit model =
    let
        data =
            intoCustomSpeedSetting model.speedSetting |> Maybe.withDefault defaultCustom
    in
    { model
        | rawMinutes = String.fromInt data.minutes
        , rawSeconds = String.fromInt data.seconds
        , rawIncrement = String.fromInt data.increment
    }


joinMatch : Model -> ( Model, Effect Msg )
joinMatch model =
    ( { model | matchConnectionStatus = MatchConnectionRequested model.rawMatchId }
    , pushUrl model.key (Route.toHref (Route.Game__Id_ { id = model.rawMatchId })) |> Effect.fromCmd
    )


{-| Requests a new syncronized match from the server.
-}
createMatch : Model -> ( Model, Effect Msg )
createMatch model =
    ( model, Api.Backend.postMatchRequest (buildTimerConfig model.speedSetting) HttpError MatchCreatedOnServer |> Effect.fromCmd )



--------------------------------------------------------------------------------
-- View code -------------------------------------------------------------------
--------------------------------------------------------------------------------


matchSetupUi : Shared.Model -> Model -> Element Msg
matchSetupUi shared model =
    Element.column [ width fill, height fill, scrollbarY ]
        [ Components.header1 (t shared.language i18nPlayPacoSako)
        , matchSetupUiInner shared model
        ]


matchSetupUiInner : Shared.Model -> Model -> Element Msg
matchSetupUiInner shared model =
    Element.column [ width (fill |> Element.maximum 1200), padding 5, spacing 5, centerX ]
        [ Element.row [ width fill, spacing 5, centerX ]
            [ joinOnlineMatchUi shared model
            , setupOnlineMatchUi shared model
            ]
        , recentGamesList shared model model.recentGames
        ]


box : Element.Color -> List (Element Msg) -> Element Msg
box color content =
    Element.el [ width fill, centerX, padding 10, Background.color color, height fill ]
        (Element.column [ width fill, centerX, spacing 7 ]
            content
        )


setupOnlineMatchUi : Shared.Model -> Model -> Element Msg
setupOnlineMatchUi shared model =
    box (Element.rgb255 220 230 220)
        [ Element.el [ centerX, Font.size 30 ] (Element.text (t shared.language i18nCreateNewGame))
        , Element.row [ width fill, spacing 7 ]
            [ speedButton
                { buttonIcon = Solid.spaceShuttle
                , caption = t shared.language i18nLightspeed
                , event = SetSpeedSetting Lightspeed
                , selected = model.speedSetting == Lightspeed
                }
            , speedButton
                { buttonIcon = Solid.bolt
                , caption = t shared.language i18nBlitz
                , event = SetSpeedSetting Blitz
                , selected = model.speedSetting == Blitz
                }
            ]
        , Element.row [ width fill, spacing 7 ]
            [ speedButton
                { buttonIcon = Solid.frog
                , caption = t shared.language i18nRapid
                , event = SetSpeedSetting Rapid
                , selected = model.speedSetting == Rapid
                }
            , speedButton
                { buttonIcon = Solid.couch
                , caption = t shared.language i18nRelaxed
                , event = SetSpeedSetting Relaxed
                , selected = model.speedSetting == Relaxed
                }
            ]
        , Element.row [ width fill, spacing 7 ]
            [ speedButton
                { buttonIcon = Solid.wrench
                , caption = t shared.language i18nCustom
                , event =
                    SetSpeedSetting
                        (intoCustomSpeedSetting model.speedSetting
                            |> Maybe.withDefault defaultCustom
                            |> Custom
                        )
                , selected = isCustom model.speedSetting
                }
            , speedButton
                { buttonIcon = Solid.dove
                , caption = t shared.language i18nNoTimer
                , event = SetSpeedSetting NoTimer
                , selected = model.speedSetting == NoTimer
                }
            ]
        , timeLimitInputLabel shared model
        , bigRoundedButton (Element.rgb255 200 210 200)
            (Just CreateMatch)
            [ Element.text (t shared.language i18nCreateMatch) ]
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


timeLimitInputLabel : Shared.Model -> Model -> Element Msg
timeLimitInputLabel shared model =
    case model.speedSetting of
        Custom _ ->
            timeLimitInputCustom shared model

        _ ->
            timeLimitLabelOnly shared model


timeLimitLabelOnly : Shared.Model -> Model -> Element Msg
timeLimitLabelOnly shared model =
    let
        ( m, s, i ) =
            t shared.language i18nChoosenTimeLimit
    in
    case intoCustomSpeedSetting model.speedSetting of
        Just { minutes, seconds, increment } ->
            Element.text <|
                String.fromInt minutes
                    ++ m
                    ++ String.fromInt seconds
                    ++ s
                    ++ String.fromInt increment
                    ++ i

        Nothing ->
            Element.text (t shared.language i18nPlayWithoutTimeLimit)


timeLimitInputCustom : Shared.Model -> Model -> Element Msg
timeLimitInputCustom shared model =
    let
        ( m, s, i ) =
            t shared.language i18nChoosenTimeLimit
    in
    Element.wrappedRow []
        [ Input.text [ width (Element.px 60) ]
            { onChange = SetRawMinutes, text = model.rawMinutes, placeholder = Nothing, label = Input.labelHidden "Minutes" }
        , Element.text m
        , Input.text [ width (Element.px 50) ]
            { onChange = SetRawSeconds, text = model.rawSeconds, placeholder = Nothing, label = Input.labelHidden "Seconds" }
        , Element.text s
        , Input.text [ width (Element.px 50) ]
            { onChange = SetRawIncrement, text = model.rawIncrement, placeholder = Nothing, label = Input.labelHidden "Increment" }
        , Element.text i
        ]


joinOnlineMatchUi : Shared.Model -> Model -> Element Msg
joinOnlineMatchUi shared model =
    box (Element.rgb255 220 220 230)
        [ Element.el [ centerX, Font.size 30 ] (Element.text (t shared.language i18nIGotAnInvite))
        , Input.text [ width fill, onKeyUpAttr [ forKey "Enter" |> fireMsg JoinMatch ] ]
            { onChange = SetRawMatchId
            , text = model.rawMatchId
            , placeholder = Just (Input.placeholder [] (Element.text (t shared.language i18nEnterMatchId)))
            , label = Input.labelLeft [ centerY ] (Element.text (t shared.language i18nMatchId))
            }
        , bigRoundedButton (Element.rgb255 200 200 210)
            (Just JoinMatch)
            [ Element.text (t shared.language i18nJoinGame) ]
        ]


{-| A button that is implemented via a vertical column.
-}
bigRoundedButton : Element.Color -> Maybe msg -> List (Element msg) -> Element msg
bigRoundedButton color event content =
    Input.button [ Background.color color, width fill, height fill, Border.rounded 5 ]
        { onPress = event
        , label = Element.column [ height fill, centerX, padding 15, spacing 10 ] content
        }


recentGamesList : Shared.Model -> Model -> WebData (List CurrentMatchState) -> Element Msg
recentGamesList shared model data =
    case data of
        RemoteData.NotAsked ->
            Input.button [ padding 10 ]
                { onPress = Just RefreshRecentGames
                , label = Element.text (t shared.language i18nRecentSearchNotAsked)
                }

        RemoteData.Loading ->
            Element.el [ padding 10 ]
                (Element.text (t shared.language i18nRecentSearchLoading))

        RemoteData.Failure _ ->
            Input.button [ padding 10 ]
                { onPress = Just RefreshRecentGames
                , label = Element.text (t shared.language i18nRecentSearchError)
                }

        RemoteData.Success games ->
            recentGamesListSuccess shared model games


recentGamesListSuccess : Shared.Model -> Model -> List CurrentMatchState -> Element Msg
recentGamesListSuccess shared model games =
    if List.isEmpty games then
        Input.button [ padding 10 ]
            { onPress = Just RefreshRecentGames
            , label = Element.text (t shared.language i18nRecentSearchNoGames)
            }

    else
        Element.wrappedRow [ width fill, spacing 5 ]
            (List.map (lazy2 recentGamesListSuccessOne shared.language) games
                ++ [ refreshButton (t shared.language i18nRecentSearchRefresh) ]
            )


refreshButton : String -> Element Msg
refreshButton caption =
    Input.button
        [ padding 10
        , Background.color (Element.rgb 0.9 0.9 0.9)
        ]
        { onPress = Just RefreshRecentGames
        , label =
            column [ spacing 10 ]
                [ icon [] Solid.redo
                    |> Element.el [ centerX, centerY ]
                    |> Element.el [ width (px 150), height (px 150) ]
                , Element.text caption |> Element.el [ centerX ]
                ]
        }


recentGamesListSuccessOne : Language -> CurrentMatchState -> Element msg
recentGamesListSuccessOne lang matchState =
    let
        position =
            Sako.initialPosition
                |> Sako.doActionsList matchState.actionHistory
                |> Maybe.map (PositionView.renderStatic WhiteBottom)
                |> Maybe.map (PositionView.viewStatic PositionView.staticViewConfig)
                |> Maybe.withDefault (Element.text matchState.key)
                |> Element.el [ width (px 150), height (px 150) ]

        gameKeyLabel =
            Element.el [ centerX ] (Element.text (t lang i18nMatch ++ " " ++ matchState.key))
    in
    Element.link
        [ padding 10
        , Background.color (Element.rgb 0.9 0.9 0.9)
        ]
        { url = Route.toHref (Route.Game__Id_ { id = matchState.key })
        , label = column [ spacing 10 ] [ position, gameKeyLabel ]
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


i18nCreateMatch : I18nToken String
i18nCreateMatch =
    I18nToken
        { english = "Create Match"
        , dutch = "Partij maken"
        , esperanto = "Krei Matĉon"
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


i18nMatch : I18nToken String
i18nMatch =
    I18nToken
        { english = "Match"
        , dutch = "Partij"
        , esperanto = "Matĉo"
        }


i18nChoosenTimeLimit : I18nToken ( String, String, String )
i18nChoosenTimeLimit =
    I18nToken
        { english = ( " minutes, ", " seconds with ", " seconds increment." )
        , dutch = ( " minuten, ", " seconden mit ", " seconden toename." )
        , esperanto = ( " minutoj, ", " sekundoj kun ", " sekundoj aldonata." )
        }
