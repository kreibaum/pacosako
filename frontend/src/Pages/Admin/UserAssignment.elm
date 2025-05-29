module Pages.Admin.UserAssignment exposing (Model, Msg, page)

import Api.Backend exposing (Replay)
import Api.Decoders exposing (PublicUserData)
import Components exposing (colorButton, grayBox, heading, textParagraph)
import Custom.Element exposing (icon)
import Effect exposing (Effect)
import Element exposing (Element, centerX, column, el, fill, height, padding, px, row, spacing, width)
import Element.Input as Input
import Fen
import FontAwesome.Solid as Solid
import Gen.Params.Admin.UserAssignment exposing (Params)
import Header
import Http
import Json.Encode as Encode
import Layout
import Page
import PositionView
import Request
import Sako
import Shared
import Svg.Custom exposing (BoardRotation(..))
import Translations as T
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared _ =
    Page.advanced
        { init = init
        , update = update
        , view = view shared
        , subscriptions = subscriptions
        }



-- INIT


type alias Model =
    { gameIdRaw : String
    , gameId : Maybe Int
    , replay : Maybe Replay
    , whitePlayerIdRaw : String
    , whitePlayerId : Maybe Int
    , whitePlayer : Maybe PublicUserData
    , blackPlayerIdRaw : String
    , blackPlayerId : Maybe Int
    , blackPlayer : Maybe PublicUserData
    , lastHttpError : Maybe String
    }


init : ( Model, Effect Msg )
init =
    ( { gameIdRaw = ""
      , gameId = Nothing
      , replay = Nothing
      , whitePlayerIdRaw = ""
      , whitePlayerId = Nothing
      , whitePlayer = Nothing
      , blackPlayerIdRaw = ""
      , blackPlayerId = Nothing
      , blackPlayer = Nothing
      , lastHttpError = Nothing
      }
    , Effect.none
    )



-- UPDATE


type Msg
    = ToShared Shared.Msg
    | NoOp
    | TypeUpdateGameId String
    | GotReplay Int Replay
    | HttpErrorReplay Http.Error
    | TypeUpdateWhitePlayerId String
    | GotWhitePlayerData Int PublicUserData
    | TypeUpdateBlackPlayerId String
    | GotBlackPlayerData Int PublicUserData
    | AssignPlayers
    | HttpErrorAssignment String


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        ToShared outMsg ->
            ( model, Effect.fromShared outMsg )

        NoOp ->
            ( model, Effect.none )

        TypeUpdateGameId gameIdRaw ->
            updateGameId gameIdRaw model

        GotReplay replayId replay ->
            if model.gameId == Just replayId then
                ( { model | replay = Just replay }, Effect.none )

            else
                ( model, Effect.none )

        HttpErrorReplay _ ->
            ( model, Effect.none )

        TypeUpdateWhitePlayerId whitePlayerIdRaw ->
            updateWhitePlayerId whitePlayerIdRaw model

        GotWhitePlayerData whitePlayerId whitePlayer ->
            if model.whitePlayerId == Just whitePlayerId then
                ( { model | whitePlayer = Just whitePlayer }, Effect.none )

            else
                ( model, Effect.none )

        TypeUpdateBlackPlayerId blackPlayerIdRaw ->
            updateBlackPlayerId blackPlayerIdRaw model

        GotBlackPlayerData blackPlayerId blackPlayer ->
            if model.blackPlayerId == Just blackPlayerId then
                ( { model | blackPlayer = Just blackPlayer }, Effect.none )

            else
                ( model, Effect.none )

        AssignPlayers ->
            assignPlayers model

        HttpErrorAssignment error ->
            ( { model | lastHttpError = Just error }, Effect.none )


updateGameId : String -> Model -> ( Model, Effect Msg )
updateGameId gameIdRaw model =
    let
        gameId =
            String.toInt gameIdRaw

        replayDownloadCmd =
            gameId
                |> Maybe.map (\gid -> Api.Backend.getReplay (String.fromInt gid) HttpErrorReplay (GotReplay gid))
                |> Maybe.withDefault Cmd.none
    in
    ( { model
        | gameIdRaw = gameIdRaw
        , gameId = gameId
        , whitePlayerIdRaw = ""
        , whitePlayerId = Nothing
        , whitePlayer = Nothing
        , blackPlayerIdRaw = ""
        , blackPlayerId = Nothing
        , blackPlayer = Nothing
        , lastHttpError = Nothing
      }
    , Effect.fromCmd replayDownloadCmd
    )


updateWhitePlayerId : String -> Model -> ( Model, Effect Msg )
updateWhitePlayerId whitePlayerIdRaw model =
    let
        whitePlayerId =
            String.toInt whitePlayerIdRaw

        playerDataDownloadCmd =
            whitePlayerId
                |> Maybe.map (\pid -> Api.Backend.getPublicUserData pid HttpErrorReplay (GotWhitePlayerData pid))
                |> Maybe.withDefault Cmd.none
    in
    ( { model
        | whitePlayerIdRaw = whitePlayerIdRaw
        , whitePlayerId = whitePlayerId
      }
    , Effect.fromCmd playerDataDownloadCmd
    )


updateBlackPlayerId : String -> Model -> ( Model, Effect Msg )
updateBlackPlayerId blackPlayerIdRaw model =
    let
        blackPlayerId =
            String.toInt blackPlayerIdRaw

        playerDataDownloadCmd =
            blackPlayerId
                |> Maybe.map (\pid -> Api.Backend.getPublicUserData pid HttpErrorReplay (GotBlackPlayerData pid))
                |> Maybe.withDefault Cmd.none
    in
    ( { model
        | blackPlayerIdRaw = blackPlayerIdRaw
        , blackPlayerId = blackPlayerId
      }
    , Effect.fromCmd playerDataDownloadCmd
    )


assignPlayers : Model -> ( Model, Effect Msg )
assignPlayers model =
    let
        req =
            model.gameId
                |> Maybe.map
                    (\gameId ->
                        Encode.object
                            [ ( "game_id", Encode.int <| gameId )
                            , ( "white_assignee"
                              , model.whitePlayerId
                                    |> Maybe.map Encode.int
                                    |> Maybe.withDefault Encode.null
                              )
                            , ( "black_assignee"
                              , model.blackPlayerId
                                    |> Maybe.map Encode.int
                                    |> Maybe.withDefault Encode.null
                              )
                            ]
                    )
                |> Maybe.map
                    (\body ->
                        Http.post
                            { url = "/api/game/backdate"
                            , body = Http.jsonBody body
                            , expect =
                                Http.expectStringResponse
                                    (\result ->
                                        case result of
                                            Ok _ ->
                                                TypeUpdateGameId (model.gameId |> Maybe.withDefault 0 |> String.fromInt)

                                            Err errorText ->
                                                HttpErrorAssignment errorText
                                    )
                                    (\response ->
                                        case response of
                                            Http.BadUrl_ url ->
                                                Err ("Bad URL: " ++ url)

                                            Http.Timeout_ ->
                                                Err "Timeout"

                                            Http.NetworkError_ ->
                                                Err "Network error"

                                            Http.BadStatus_ _ stringBody ->
                                                Err stringBody

                                            Http.GoodStatus_ _ _ ->
                                                Ok ()
                                    )
                            }
                    )
    in
    case req of
        Just request ->
            ( { model | lastHttpError = Nothing }, Effect.fromCmd request )

        Nothing ->
            ( model, Effect.none )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- VIEW


view : Shared.Model -> Model -> View Msg
view shared model =
    { title = T.adminUserAssignmentPageTitle
    , element =
        Header.wrapWithHeaderV2 shared
            ToShared
            { isRouteHighlighted = \_ -> False
            , isWithBackground = True
            }
            (Layout.textPageWrapper (userAssignmentView shared model))
    }


userAssignmentView : Shared.Model -> Model -> List (Element Msg)
userAssignmentView shared model =
    [ grayBox []
        [ heading T.adminUserAssignmentPageTitle
        , textParagraph T.adminUserAssignmentL1
        ]
    , grayBox []
        [ Input.text []
            { onChange = TypeUpdateGameId
            , text = model.gameIdRaw
            , placeholder = Just (Input.placeholder [] (Element.text T.enterMatchId))
            , label = Input.labelHidden T.matchId
            }
            |> el [ padding 10 ]
        ]
    , grayBox []
        [ model.replay
            |> Maybe.map (\replay -> gamePreview shared model replay)
            |> Maybe.withDefault Element.none
        ]
    , model.lastHttpError
        |> Maybe.map
            (\e ->
                grayBox []
                    [ textParagraph e ]
            )
        |> Maybe.withDefault Element.none
    , grayBox []
        [ colorButton []
            { background = Element.rgb255 51 191 255
            , backgroundHover = Element.rgb255 102 206 255
            , onPress = Just AssignPlayers
            , buttonIcon = icon [ centerX ] Solid.checkCircle
            , caption = T.adminUserAssignmentPerform
            }
            |> el [ padding 10 ]
        ]
    ]


gamePreview : Shared.Model -> Model -> Replay -> Element Msg
gamePreview shared model replay =
    column []
        [ heading replay.key
        , replay.blackPlayer
            |> Maybe.map playerLabel
            |> Maybe.withDefault (playerInput model.blackPlayerIdRaw TypeUpdateBlackPlayerId model.blackPlayer)
        , gamePreviewImage shared replay
        , replay.whitePlayer
            |> Maybe.map playerLabel
            |> Maybe.withDefault (playerInput model.whitePlayerIdRaw TypeUpdateWhitePlayerId model.whitePlayer)
        ]


playerInput : String -> (String -> Msg) -> Maybe PublicUserData -> Element Msg
playerInput inputText onChange playerPreview =
    row [ padding 10 ]
        [ Input.text [ spacing 5 ]
            { onChange = onChange
            , text = inputText
            , placeholder = Just (Input.placeholder [] (Element.text T.adminUserAssignmentEnterId))
            , label = Input.labelHidden T.adminUserAssignmentEnterId
            }
        , playerPreview
            |> Maybe.map playerLabel
            |> Maybe.withDefault Element.none
        ]


playerLabel : PublicUserData -> Element Msg
playerLabel user =
    row [ spacing 5, height fill, padding 10 ]
        [ Element.image [ width (px 30), height (px 30) ]
            { src = "/p/" ++ user.avatar, description = "" }
        , Element.text user.name
        ]


gamePreviewImage : Shared.Model -> Replay -> Element Msg
gamePreviewImage shared replay =
    let
        actionHistory =
            List.map Tuple.first replay.actions

        position =
            replay.setupOptions.startingFen
                |> Fen.parseFen
                |> Maybe.andThen (Sako.doActionsList actionHistory)
    in
    position
        |> Maybe.map (PositionView.renderStatic WhiteBottom)
        |> Maybe.map (PositionView.viewStatic (PositionView.staticViewConfig shared.colorConfig))
        |> Maybe.map (Element.el [ width (px 400), height (px 400) ])
        |> Maybe.withDefault Element.none
