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
import Element.Lazy exposing (lazy)
import FontAwesome.Icon exposing (Icon)
import FontAwesome.Solid as Solid
import Gen.Route as Route
import Header
import Http
import Page
import PositionView exposing (BoardDecoration(..), DraggingPieces(..), Highlight(..))
import RemoteData exposing (WebData)
import Request
import Sako exposing (Tile(..))
import Shared
import Svg.Custom exposing (BoardRotation(..))
import Timer
import Translations as T
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
        Header.wrapWithHeader shared ToShared (matchSetupUi model)
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


matchSetupUi : Model -> Element Msg
matchSetupUi model =
    Element.column [ width fill, height fill, scrollbarY ]
        [ Components.header1 T.playPacoSako
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
        [ Element.el [ centerX, Font.size 30 ] (Element.text T.createNewGame)
        , Element.row [ width fill, spacing 7 ]
            [ speedButton
                { buttonIcon = Solid.spaceShuttle
                , caption = T.lightspeed
                , event = SetSpeedSetting Lightspeed
                , selected = model.speedSetting == Lightspeed
                }
            , speedButton
                { buttonIcon = Solid.bolt
                , caption = T.blitz
                , event = SetSpeedSetting Blitz
                , selected = model.speedSetting == Blitz
                }
            ]
        , Element.row [ width fill, spacing 7 ]
            [ speedButton
                { buttonIcon = Solid.frog
                , caption = T.rapid
                , event = SetSpeedSetting Rapid
                , selected = model.speedSetting == Rapid
                }
            , speedButton
                { buttonIcon = Solid.couch
                , caption = T.relaxed
                , event = SetSpeedSetting Relaxed
                , selected = model.speedSetting == Relaxed
                }
            ]
        , Element.row [ width fill, spacing 7 ]
            [ speedButton
                { buttonIcon = Solid.wrench
                , caption = T.custom
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
                , caption = T.noTimer
                , event = SetSpeedSetting NoTimer
                , selected = model.speedSetting == NoTimer
                }
            ]
        , timeLimitInputLabel model
        , bigRoundedButton (Element.rgb255 200 210 200)
            (Just CreateMatch)
            [ Element.text T.createMatch ]
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


timeLimitInputLabel : Model -> Element Msg
timeLimitInputLabel model =
    case model.speedSetting of
        Custom _ ->
            timeLimitInputCustom model

        _ ->
            timeLimitLabelOnly model


timeLimitLabelOnly : Model -> Element Msg
timeLimitLabelOnly model =
    let
        ( m, s, i ) =
            i18nChoosenTimeLimit
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
            Element.text T.playWithoutTimeLimit


timeLimitInputCustom : Model -> Element Msg
timeLimitInputCustom model =
    let
        ( m, s, i ) =
            i18nChoosenTimeLimit
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


joinOnlineMatchUi : Model -> Element Msg
joinOnlineMatchUi model =
    box (Element.rgb255 220 220 230)
        [ Element.el [ centerX, Font.size 30 ] (Element.text T.iGotAnInvite)
        , Input.text [ width fill, onKeyUpAttr [ forKey "Enter" |> fireMsg JoinMatch ] ]
            { onChange = SetRawMatchId
            , text = model.rawMatchId
            , placeholder = Just (Input.placeholder [] (Element.text T.enterMatchId))
            , label = Input.labelLeft [ centerY ] (Element.text T.matchId)
            }
        , bigRoundedButton (Element.rgb255 200 200 210)
            (Just JoinMatch)
            [ Element.text T.joinGame ]
        ]


{-| A button that is implemented via a vertical column.
-}
bigRoundedButton : Element.Color -> Maybe msg -> List (Element msg) -> Element msg
bigRoundedButton color event content =
    Input.button [ Background.color color, width fill, height fill, Border.rounded 5 ]
        { onPress = event
        , label = Element.column [ height fill, centerX, padding 15, spacing 10 ] content
        }


recentGamesList : WebData (List CurrentMatchState) -> Element Msg
recentGamesList data =
    case data of
        RemoteData.NotAsked ->
            Input.button [ padding 10 ]
                { onPress = Just RefreshRecentGames
                , label = Element.text T.recentSearchNotAsked
                }

        RemoteData.Loading ->
            Element.el [ padding 10 ]
                (Element.text T.recentSearchLoading)

        RemoteData.Failure _ ->
            Input.button [ padding 10 ]
                { onPress = Just RefreshRecentGames
                , label = Element.text T.recentSearchError
                }

        RemoteData.Success games ->
            recentGamesListSuccess games


recentGamesListSuccess : List CurrentMatchState -> Element Msg
recentGamesListSuccess games =
    if List.isEmpty games then
        Input.button [ padding 10 ]
            { onPress = Just RefreshRecentGames
            , label = Element.text T.recentSearchNoGames
            }

    else
        Element.wrappedRow [ width fill, spacing 5 ]
            (List.map (lazy recentGamesListSuccessOne) games
                ++ [ refreshButton T.recentSearchRefresh ]
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


recentGamesListSuccessOne : CurrentMatchState -> Element msg
recentGamesListSuccessOne matchState =
    let
        position =
            Sako.initialPosition
                |> Sako.doActionsList matchState.actionHistory
                |> Maybe.map (PositionView.renderStatic WhiteBottom)
                |> Maybe.map (PositionView.viewStatic PositionView.staticViewConfig)
                |> Maybe.withDefault (Element.text matchState.key)
                |> Element.el [ width (px 150), height (px 150) ]

        gameKeyLabel =
            Element.el [ centerX ] (Element.text (T.match ++ " " ++ matchState.key))
    in
    Element.link
        [ padding 10
        , Background.color (Element.rgb 0.9 0.9 0.9)
        ]
        { url = Route.toHref (Route.Game__Id_ { id = matchState.key })
        , label = column [ spacing 10 ] [ position, gameKeyLabel ]
        }


i18nChoosenTimeLimit : ( String, String, String )
i18nChoosenTimeLimit =
    case T.compiledLanguage of
        T.English ->
            ( " minutes, ", " seconds with ", " seconds increment." )

        T.Dutch ->
            ( " minuten, ", " seconden mit ", " seconden toename." )

        T.Esperanto ->
            ( " minutoj, ", " sekundoj kun ", " sekundoj aldonata." )
