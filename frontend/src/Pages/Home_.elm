module Pages.Home_ exposing (Model, Msg, Params, page)

import Ai exposing (AiInitProgress)
import Api.Backend
import Api.Decoders exposing (CompressedMatchState)
import Api.LocalStorage exposing (CustomTimer)
import Api.Ports as Ports
import Browser.Navigation exposing (pushUrl)
import Components
import Content.References
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
import Layout
import Page
import Reactive
import RemoteData exposing (WebData)
import Request
import Sako exposing (Color(..))
import Sako.FenView
import Shared
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
        Header.wrapWithHeaderV2 shared
            ToShared
            { isRouteHighlighted = \r -> r == Route.Home_
            , isWithBackground = True
            }
            (Layout.vScollBox [ matchSetupUi shared model ])
    }


init : Shared.Model -> ( Model, Effect Msg )
init shared =
    ( { rawMatchId = ""
      , matchConnectionStatus = NoMatchConnection
      , speedSetting = Blitz
      , rawMinutes = ""
      , rawSeconds = ""
      , rawIncrement = ""
      , repetitionDraw = True
      , recentGames = RemoteData.Loading
      , key = shared.key
      , aiViewVisible = False
      , aiColorChoice = Nothing
      }
    , refreshRecentGames |> Effect.fromCmd
    )


type Msg
    = SetRawMatchId String
    | JoinMatch
    | CreateMatch
    | MatchConfirmedByServer String
    | MatchNotFoundByServer String
    | SetSpeedSetting SpeedSetting
    | SetRawMinutes String
    | SetRawSeconds String
    | SetRawIncrement String
    | SetRepetitionDraw Bool
    | RefreshRecentGames
    | GotRecentGames (List CompressedMatchState)
    | ErrorRecentGames Http.Error
    | HttpError Http.Error
    | ToShared Shared.Msg
    | SetAiViewVisible Bool
    | SetAiColorChoice (Maybe Sako.Color)


type alias Model =
    { rawMatchId : String
    , matchConnectionStatus : MatchConnectionStatus
    , speedSetting : SpeedSetting
    , rawMinutes : String
    , rawSeconds : String
    , rawIncrement : String
    , repetitionDraw : Bool
    , recentGames : WebData (List CompressedMatchState)
    , key : Browser.Navigation.Key
    , aiViewVisible : Bool
    , aiColorChoice : Maybe Sako.Color
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
    | MatchCreationRequested
    | MatchConnectionRequested
    | MatchNotFound String


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        SetRawMatchId rawMatchId ->
            ( { model | rawMatchId = rawMatchId }, Effect.none )

        JoinMatch ->
            tryJoinMatch model

        CreateMatch ->
            createMatch model

        MatchConfirmedByServer newId ->
            joinMatch { model | rawMatchId = newId }

        MatchNotFoundByServer newId ->
            ( { model | matchConnectionStatus = MatchNotFound newId }, Effect.none )

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
            ( { model | recentGames = RemoteData.Failure error }
            , Ports.logToConsole (Api.Backend.describeError error) |> Effect.fromCmd
            )

        RefreshRecentGames ->
            ( { model | recentGames = RemoteData.Loading }, refreshRecentGames |> Effect.fromCmd )

        HttpError error ->
            ( model, Ports.logToConsole (Api.Backend.describeError error) |> Effect.fromCmd )

        ToShared outMsg ->
            ( model, Effect.fromShared outMsg )

        SetRepetitionDraw repetitionDrawEnabled ->
            ( { model | repetitionDraw = repetitionDrawEnabled }, Effect.none )

        SetAiViewVisible aiViewVisible ->
            ( { model | aiViewVisible = aiViewVisible }
            , if aiViewVisible then
                Effect.fromShared Shared.StartUpAi

              else
                Effect.none
            )

        SetAiColorChoice maybeColor ->
            ( { model | aiColorChoice = maybeColor }, Effect.none )


refreshRecentGames : Cmd Msg
refreshRecentGames =
    Api.Backend.getRecentGameKeys ErrorRecentGames GotRecentGames


{-| Parse the rawTimeLimit into an integer and take it over to the time limit if
parsing is successful.
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


tryJoinMatch : Model -> ( Model, Effect Msg )
tryJoinMatch model =
    if String.isEmpty model.rawMatchId then
        ( { model | matchConnectionStatus = MatchNotFound "" }, Effect.none )

    else
        ( { model | matchConnectionStatus = MatchConnectionRequested }
        , Api.Backend.checkGameExists model.rawMatchId
            HttpError
            (\exists ->
                if exists then
                    MatchConfirmedByServer model.rawMatchId

                else
                    MatchNotFoundByServer model.rawMatchId
            )
            |> Effect.fromCmd
        )


joinMatch : Model -> ( Model, Effect Msg )
joinMatch model =
    ( { model | matchConnectionStatus = MatchConnectionRequested }
    , pushUrl model.key (Route.toHref (Route.Game__Id_ { id = model.rawMatchId })) |> Effect.fromCmd
    )


{-| Requests a new syncronized match from the server.
-}
createMatch : Model -> ( Model, Effect Msg )
createMatch model =
    ( { model | matchConnectionStatus = MatchCreationRequested }
    , Effect.batch
        [ Api.Backend.postMatchRequest
            { timer = buildTimerConfig model.speedSetting
            , safeMode = True
            , drawAfterNRepetitions =
                if model.repetitionDraw then
                    3

                else
                    0
            , aiSideRequest =
                if model.aiViewVisible then
                    Just { modelName = "hedwig", modelStrength = 0, modelTemperature = 0.05, color = model.aiColorChoice }

                else
                    Nothing
            }
            HttpError
            MatchConfirmedByServer
            |> Effect.fromCmd
        , case model.speedSetting of
            Custom data ->
                Effect.fromShared
                    (Shared.AddRecentCustomTimer data)

            _ ->
                Effect.none
        ]
    )



--------------------------------------------------------------------------------
-- View code -------------------------------------------------------------------
--------------------------------------------------------------------------------


matchSetupUi : Shared.Model -> Model -> Element Msg
matchSetupUi shared model =
    case Reactive.classify shared.windowSize of
        Reactive.Phone ->
            matchSetupUiPhone shared model

        Reactive.Tablet ->
            matchSetupUiTablet shared model

        Reactive.Desktop ->
            matchSetupUiDesktop shared model


matchSetupUiDesktop : Shared.Model -> Model -> Element Msg
matchSetupUiDesktop shared model =
    Element.column [ width (fill |> Element.maximum 1120), spacing 15, centerX, paddingXY 10 40 ]
        [ Element.row [ height fill, width fill, spacing 15, centerX ]
            [ column [ height fill, width fill, spacing 15 ]
                [ setupOnlineMatchUi shared model
                , configureAiUi shared model
                , joinOnlineMatchUi model
                ]
            , column [ height fill, width fill, spacing 15 ]
                [ Content.References.posterumCupInvite
                , Content.References.discordInvite
                , Content.References.officialWebsiteLink
                , Content.References.twitchLink
                , Content.References.translationSuggestion
                , Content.References.gitHubLink
                ]
            ]
        , recentGamesList shared model.recentGames
        ]


matchSetupUiTablet : Shared.Model -> Model -> Element Msg
matchSetupUiTablet shared model =
    Element.column [ width (fill |> Element.maximum 1120), spacing 10, centerX, paddingXY 10 40 ]
        [ setupOnlineMatchUi shared model
        , joinOnlineMatchUi model
        , configureAiUi shared model
        , Content.References.posterumCupInvite
        , row [ width fill, spacing 10 ]
            [ Content.References.discordInvite
            , Content.References.officialWebsiteLink
            ]
        , row [ height fill, width fill, spacing 10 ]
            [ Content.References.twitchLink
            , Content.References.gitHubLink
            ]
        , Content.References.translationSuggestion
        , recentGamesList shared model.recentGames
        ]


matchSetupUiPhone : Shared.Model -> Model -> Element Msg
matchSetupUiPhone shared model =
    Element.column [ width fill, spacing 10, centerX, paddingXY 10 20 ]
        [ setupOnlineMatchUi shared model
        , configureAiUi shared model
        , joinOnlineMatchUi model
        , Content.References.posterumCupInvite
        , Content.References.discordInvite
        , Content.References.officialWebsiteLink
        , Content.References.twitchLink
        , Content.References.translationSuggestion
        , Content.References.gitHubLink
        , recentGamesList shared model.recentGames
        ]


setupOnlineMatchUi : Shared.Model -> Model -> Element Msg
setupOnlineMatchUi shared model =
    let
        fontSize =
            case Reactive.classify shared.windowSize of
                Reactive.Phone ->
                    16

                Reactive.Tablet ->
                    20

                Reactive.Desktop ->
                    20
    in
    Element.el [ height fill, width fill, centerX, Background.color (Element.rgba255 255 255 255 0.6), Border.rounded 5, Element.alignTop ]
        (Element.column [ width fill, centerX, spacing 7, padding 10 ]
            [ Element.el
                [ centerX
                , Font.size 30
                , Font.color (Element.rgb255 100 100 100)
                , Element.paddingXY 0 10
                ]
                (Element.text T.createNewGame)
            , Element.row [ width fill, spacing 7 ]
                [ speedButton
                    { buttonIcon = Solid.spaceShuttle
                    , caption = T.lightspeed
                    , event = SetSpeedSetting Lightspeed
                    , selected = model.speedSetting == Lightspeed
                    , fontSize = fontSize
                    }
                , speedButton
                    { buttonIcon = Solid.bolt
                    , caption = T.blitz
                    , event = SetSpeedSetting Blitz
                    , selected = model.speedSetting == Blitz
                    , fontSize = fontSize
                    }
                ]
            , Element.row [ width fill, spacing 7 ]
                [ speedButton
                    { buttonIcon = Solid.frog
                    , caption = T.rapid
                    , event = SetSpeedSetting Rapid
                    , selected = model.speedSetting == Rapid
                    , fontSize = fontSize
                    }
                , speedButton
                    { buttonIcon = Solid.couch
                    , caption = T.relaxed
                    , event = SetSpeedSetting Relaxed
                    , selected = model.speedSetting == Relaxed
                    , fontSize = fontSize
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
                    , fontSize = fontSize
                    }
                , speedButton
                    { buttonIcon = Solid.dove
                    , caption = T.noTimer
                    , event = SetSpeedSetting NoTimer
                    , selected = model.speedSetting == NoTimer
                    , fontSize = fontSize
                    }
                ]
            , recentTimerSettings model fontSize shared.recentCustomTimes
            , el [ centerX ] (Element.paragraph [] [ timeLimitInputLabel model ])
            , el [ centerX ] (Element.paragraph [] [ repetitionDrawToggle model ])
            , if isTimerOk (buildTimerConfig model.speedSetting) then
                row [ width fill, spacing 10 ]
                    [ createMatchButton (not model.aiViewVisible)
                    , aiToggleButton model
                    ]

              else
                column [ centerX, spacing 7 ]
                    [ el [ centerX ] (Element.paragraph [ Font.bold ] [ Element.text T.timerMustBePositive ])
                    , row [ width fill, spacing 10 ]
                        [ createMatchButton False
                        , aiToggleButton model
                        ]
                    ]
            ]
        )


createMatchButton : Bool -> Element Msg
createMatchButton enable =
    if enable then
        Components.colorButton [ centerX ]
            { background = Element.rgb255 41 204 57
            , backgroundHover = Element.rgb255 68 229 84
            , onPress = Just CreateMatch
            , buttonIcon = icon [ centerX ] Solid.plusCircle
            , caption = T.createMatch
            }

    else
        Components.colorButton [ centerX ]
            { background = Element.rgb255 200 200 200
            , backgroundHover = Element.rgb255 200 200 200
            , onPress = Nothing
            , buttonIcon = icon [ centerX ] Solid.plusCircle
            , caption = T.createMatch
            }


aiToggleButton : Model -> Element Msg
aiToggleButton model =
    Components.colorButton [ centerX ]
        { background = Element.rgb255 191 19 113
        , backgroundHover = Element.rgb255 229 22 136
        , onPress = Just (SetAiViewVisible (not model.aiViewVisible))
        , buttonIcon = icon [ centerX ] Solid.robot
        , caption = T.playWithAi
        }


isTimerOk : Maybe Timer.TimerConfig -> Bool
isTimerOk timerConfig =
    timerConfig
        |> Maybe.map (\t -> Timer.isTimerOk t)
        |> Maybe.withDefault True


{-| If the user has previously used a custom timer, they probably want to use it
again. So we present the last two timers they used as choices to play again.
-}
recentTimerSettings : Model -> Int -> List CustomTimer -> Element Msg
recentTimerSettings model fontSize recentCustomTimes =
    if List.isEmpty recentCustomTimes then
        Element.none

    else
        Element.row [ width fill, spacing 7 ]
            (List.map (oneRecentTimerSetting model fontSize) recentCustomTimes)


oneRecentTimerSetting : Model -> Int -> CustomTimer -> Element Msg
oneRecentTimerSetting model fontSize data =
    speedButton
        { buttonIcon = Solid.userClock
        , caption =
            String.fromInt data.minutes
                ++ "m "
                ++ String.fromInt data.seconds
                ++ "s +"
                ++ String.fromInt data.increment
                ++ "s"
        , event = SetSpeedSetting (Custom data)
        , selected = model.speedSetting == Custom data
        , fontSize = fontSize
        }


speedButton :
    { buttonIcon : Icon
    , caption : String
    , event : Msg
    , selected : Bool
    , fontSize : Int
    }
    -> Element Msg
speedButton config =
    Input.button
        [ Background.color (speedButtonColor config.selected)
        , Element.mouseOver [ Background.color (Element.rgb255 200 200 200) ]
        , width fill
        , height fill
        , Border.rounded 5
        ]
        { onPress = Just config.event
        , label =
            Element.row [ height fill, padding 15, spacing 10 ]
                [ el [ width (px 30) ] (icon [ centerX ] config.buttonIcon)
                , Element.el [ Font.size config.fontSize ] (Element.text config.caption)
                ]
        }


speedButtonColor : Bool -> Element.Color
speedButtonColor selected =
    if selected then
        Element.rgb255 180 180 180

    else
        Element.rgb255 220 220 220


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
    column [ width fill ]
        [ row [ spacing 5, width fill ]
            [ Input.text [ width (Element.px 50), padding 5 ]
                { onChange = SetRawMinutes, text = model.rawMinutes, placeholder = Nothing, label = Input.labelRight [ width fill ] (Element.text m) }
            ]
        , row [ spacing 5, width fill ]
            [ Input.text [ width (Element.px 50), padding 5 ]
                { onChange = SetRawSeconds, text = model.rawSeconds, placeholder = Nothing, label = Input.labelRight [ width fill ] (Element.text s) }
            ]
        , row [ spacing 5, width fill ]
            [ Input.text [ width (Element.px 50), padding 5 ]
                { onChange = SetRawIncrement, text = model.rawIncrement, placeholder = Nothing, label = Input.labelRight [ width fill ] (Element.text i) }
            ]
        ]


repetitionDrawToggle : Model -> Element Msg
repetitionDrawToggle model =
    Input.checkbox []
        { onChange = SetRepetitionDraw
        , icon = Input.defaultCheckbox
        , checked = model.repetitionDraw
        , label =
            Input.labelRight []
                (text T.enableRepetitionDraw)
        }


configureAiUi : Shared.Model -> Model -> Element Msg
configureAiUi shared model =
    if model.aiViewVisible then
        Components.grayBox [ padding 10, spacing 10 ]
            [ Element.paragraph [] [ Element.text T.playWithAiL1 ]
            , wrappedRow [ spacing 10, centerX ]
                [ aiColorChoiceButton model.aiColorChoice (Just White) Solid.robot T.gameWhite
                , aiColorChoiceButton model.aiColorChoice Nothing Solid.dice T.playWithAiColorRandom
                , aiColorChoiceButton model.aiColorChoice (Just Black) Solid.robot T.gameBlack
                ]
            , wrappedRow [ spacing 10, centerX ]
                [ createMatchButton
                    (isTimerOk (buildTimerConfig model.speedSetting)
                        && Ai.isInitialized shared.aiState
                    )
                , Components.colorButton [ centerX ]
                    { background = Element.rgb255 255 68 51
                    , backgroundHover = Element.rgb255 255 102 102
                    , onPress = Just (SetAiViewVisible False)
                    , buttonIcon = icon [ centerX ] Solid.times
                    , caption = T.playWithAiRemoveAi
                    }
                ]
            , case shared.aiState of
                Ai.NotInitialized progress ->
                    Ai.aiProgressLabel progress

                _ ->
                    Element.none
            ]

    else
        Element.none


aiColorChoiceButton : Maybe Sako.Color -> Maybe Sako.Color -> Icon -> String -> Element Msg
aiColorChoiceButton modelColor buttonColor captionIcon caption =
    if modelColor == buttonColor then
        Components.colorButton []
            { background = Element.rgb255 180 180 180
            , backgroundHover = Element.rgb255 180 180 180
            , onPress = Nothing
            , buttonIcon = icon [ centerX ] captionIcon
            , caption = caption
            }

    else
        Components.colorButton []
            { background = Element.rgb255 220 220 220
            , backgroundHover = Element.rgb255 200 200 200
            , onPress = Just (SetAiColorChoice buttonColor)
            , buttonIcon = icon [ centerX ] captionIcon
            , caption = caption
            }


joinOnlineMatchUi : Model -> Element Msg
joinOnlineMatchUi model =
    Components.grayBox [ padding 10 ]
        [ Element.el
            [ centerX
            , Font.size 30
            , Font.color (Element.rgb255 100 100 100)
            , Element.paddingXY 0 10
            ]
            (Element.text T.iGotAnInvite)
        , row [ spacing 10, centerX ]
            [ Input.text [ width fill, onKeyUpAttr [ forKey "Enter" |> fireMsg JoinMatch ] ]
                { onChange = SetRawMatchId
                , text = model.rawMatchId
                , placeholder = Just (Input.placeholder [] (Element.text T.enterMatchId))
                , label = Input.labelHidden T.matchId
                }
            , Input.button
                [ Background.color (Element.rgb255 51 191 255)
                , Element.mouseOver [ Background.color (Element.rgb255 102 206 255) ]
                , centerX
                , Border.rounded 5
                ]
                { onPress = Just JoinMatch
                , label =
                    Element.row
                        [ height fill
                        , centerX
                        , Element.paddingEach { top = 15, right = 20, bottom = 15, left = 20 }
                        , spacing 5
                        ]
                        [ el [ width (px 20) ] (icon [ centerX ] Solid.arrowCircleRight)
                        , Element.text T.joinGame
                        ]
                }
            ]
        , case model.matchConnectionStatus of
            MatchNotFound matchId ->
                Element.el [ centerX, Font.color (Element.rgb255 255 0 0), Element.paddingXY 0 10 ]
                    (Element.text (String.replace "{0}" matchId T.joinGameNotFound))

            _ ->
                Element.none
        ]


recentGamesList : Shared.Model -> WebData (List CompressedMatchState) -> Element Msg
recentGamesList shared data =
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
            recentGamesListSuccess shared games


recentGamesListSuccess : Shared.Model -> List CompressedMatchState -> Element Msg
recentGamesListSuccess shared games =
    Element.column [ centerX ]
        [ Element.el
            [ centerX
            , Font.size 30
            , Font.color (Element.rgb255 100 100 100)
            , Element.paddingXY 0 10
            ]
            (Element.paragraph [] [ Element.text T.watchLatestMatches ])
        , if List.isEmpty games then
            refreshButton

          else
            Element.wrappedRow [ width fill, spacing 5 ]
                (List.map (lazy (recentGamesListSuccessOne shared)) games
                    ++ [ refreshButton ]
                )
        ]


refreshButton : Element Msg
refreshButton =
    Input.button
        [ padding 10
        , Background.color (Element.rgba 1 1 1 0.6)
        , Element.mouseOver [ Background.color (Element.rgba 1 1 1 1) ]
        , Border.rounded 5
        ]
        { onPress = Just RefreshRecentGames
        , label =
            column [ spacing 10 ]
                [ icon [] Solid.redo
                    |> Element.el [ centerX, centerY ]
                    |> Element.el [ width (px 150), height (px 150) ]
                , Element.text T.recentSearchRefresh |> Element.el [ centerX ]
                ]
        }


recentGamesListSuccessOne : Shared.Model -> CompressedMatchState -> Element msg
recentGamesListSuccessOne shared matchState =
    let
        position =
            Sako.FenView.viewFenString { fen = matchState.fen, colorConfig = shared.colorConfig, size = 150 }

        gameKeyLabel =
            Element.el [ centerX ] (Element.text (T.match ++ " " ++ matchState.key))
    in
    Element.link
        [ padding 10
        , Background.color (Element.rgba 1 1 1 0.6)
        , Element.mouseOver [ Background.color (Element.rgba 1 1 1 1) ]
        , Border.rounded 5
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

        T.German ->
            ( " Minuten, ", " Sekunden und ", " Sekunden Inkrement." )

        T.Swedish ->
            ( " minuter, ", " sekunder med ", " sekunders steg." )

        T.Spanish ->
            ( " minutos, ", " segundos con ", " segundos de incremento." )
