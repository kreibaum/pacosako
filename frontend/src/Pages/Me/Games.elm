module Pages.Me.Games exposing (Model, Msg, page)

import Api.Backend
import Api.Decoders exposing (CompressedMatchState, PublicUserData)
import Api.Ports
import Components
import Custom.Element exposing (icon)
import Effect exposing (Effect)
import Element exposing (Element, alignRight, centerX, column, el, fill, height, padding, px, row, spacing, width)
import Element.Font as Font
import FontAwesome.Solid as Solid
import Gen.Params.Me.Games exposing (Params)
import Header
import Http
import Layout
import Page
import RemoteData exposing (WebData)
import Request
import Sako.FenView
import Shared
import Svg.PlayerLabel as PlayerLabel
import Timer exposing (classifyDuration, expectedTimeLimit)
import Translations as T
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared _ =
    Page.advanced
        { init = init
        , update = update
        , view = view shared
        , subscriptions = \_ -> Sub.none
        }



-- INIT


type alias Model =
    { offset : Int
    , myGames : WebData Api.Backend.PagedGames
    }


init : ( Model, Effect Msg )
init =
    ( { offset = 0
      , myGames = RemoteData.Loading
      }
    , Api.Backend.getMyGames { offset = 0, limit = 10 }
        MyGamesErrored
        MyGamesLoaded
        |> Effect.fromCmd
    )



-- UPDATE


type Msg
    = ToShared Shared.Msg
    | MyGamesLoaded Api.Backend.PagedGames
    | MyGamesErrored Http.Error
    | SetOffset Int


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        ToShared outMsg ->
            ( model, Effect.fromShared outMsg )

        MyGamesLoaded games ->
            ( { model
                | myGames = RemoteData.Success games
                , offset = min model.offset games.totalGames
              }
            , Effect.none
            )

        MyGamesErrored error ->
            ( { model | myGames = RemoteData.Failure error }
            , Api.Ports.logToConsole (Api.Backend.describeError error) |> Effect.fromCmd
            )

        SetOffset offset ->
            ( { model | offset = offset, myGames = RemoteData.Loading }
            , Api.Backend.getMyGames { offset = offset, limit = 10 }
                MyGamesErrored
                MyGamesLoaded
                |> Effect.fromCmd
            )



-- VIEW


view : Shared.Model -> Model -> View Msg
view shared model =
    { title = T.mePageTitle
    , element =
        Header.wrapWithHeaderV2 shared
            ToShared
            { isRouteHighlighted = \_ -> False
            , isWithBackground = True
            }
            (Layout.textPageWrapper
                [ case model.myGames of
                    RemoteData.Success myGames ->
                        viewGames shared model myGames

                    _ ->
                        Element.none
                ]
            )
    }


viewGames : Shared.Model -> Model -> Api.Backend.PagedGames -> Element Msg
viewGames shared model myGames =
    column [ width fill, spacing 5 ]
        (navigation model
            :: (myGames.games
                    |> List.map (viewOneGame shared)
               )
        )


navigation : Model -> Element Msg
navigation model =
    Element.row [ width fill ]
        [ Components.colorButton []
            { background = Element.rgba 1 1 1 0.6
            , backgroundHover = Element.rgba 1 1 1 1
            , onPress = Just (SetOffset (model.offset - 10 |> max 0))
            , buttonIcon = icon [ centerX ] Solid.angleLeft
            , caption = T.navigateNewerGames
            }
        , Components.colorButton [ alignRight ]
            { background = Element.rgba 1 1 1 0.6
            , backgroundHover = Element.rgba 1 1 1 1
            , onPress = Just (SetOffset (model.offset + 10))
            , buttonIcon = icon [ centerX ] Solid.angleRight
            , caption = T.navigateOlderGames
            }
        ]


viewOneGame : Shared.Model -> CompressedMatchState -> Element Msg
viewOneGame shared game =
    let
        position =
            Sako.FenView.viewFenString { fen = game.fen, colorConfig = shared.colorConfig, size = 150 }

        profileWhite =
            Maybe.withDefault PlayerLabel.anonymousProfile game.whitePlayer

        profileBlack =
            Maybe.withDefault PlayerLabel.anonymousProfile game.blackPlayer

        emojis =
            PlayerLabel.victoryStateToText game.gameState Nothing

        duration =
            game.timer
                |> Maybe.map .config
                |> Maybe.map expectedTimeLimit
                |> Maybe.map classifyDuration
                |> Maybe.withDefault Timer.Classical

        durationIcon =
            case duration of
                Timer.Lightspeed ->
                    Solid.spaceShuttle

                Timer.Blitz ->
                    Solid.bolt

                Timer.Rapid ->
                    Solid.frog

                Timer.Classical ->
                    Solid.couch
    in
    Element.link [ width fill ]
        { url = "/replay/" ++ game.key
        , label =
            Components.activeGrayBox
                [ row [ padding 5, spacing 5 ]
                    [ el [ width (px 50) ] (icon [ Font.size 40, centerX ] durationIcon)
                    , position
                    , column [ height fill, padding 10 ]
                        [ Element.text (T.match ++ " " ++ game.key)
                        , row [ spacing 5, height fill ]
                            [ Element.text "B:", playerLabel profileBlack emojis.black ]
                        , row [ spacing 5, height fill ]
                            [ Element.text "W:", playerLabel profileWhite emojis.white ]
                        ]
                    ]
                ]
        }


playerLabel : PublicUserData -> String -> Element Msg
playerLabel user emoji =
    row [ spacing 5, height fill ]
        [ Element.image [ width (px 30), height (px 30) ]
            { src = "/p/" ++ user.avatar, description = "" }
        , Element.text (user.name ++ emoji)
        ]
