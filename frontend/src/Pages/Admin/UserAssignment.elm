module Pages.Admin.UserAssignment exposing (Model, Msg, page)

import Api.Backend exposing (Replay)
import Api.Decoders exposing (PublicUserData)
import Components exposing (grayBox, heading, textParagraph)
import Effect exposing (Effect)
import Element exposing (Element, column, el, fill, height, padding, px, row, spacing, width)
import Element.Input as Input
import Gen.Params.Admin.UserAssignment exposing (Params)
import Header
import Http
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
page shared req =
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
    , whitePlayerId : String
    , blackPlayerId : String
    }


init : ( Model, Effect Msg )
init =
    ( { gameIdRaw = ""
      , gameId = Nothing
      , replay = Nothing
      , whitePlayerId = ""
      , blackPlayerId = ""
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
    | TypeUpdateBlackPlayerId String


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

        TypeUpdateWhitePlayerId whitePlayerId ->
            ( { model | whitePlayerId = whitePlayerId }, Effect.none )

        TypeUpdateBlackPlayerId blackPlayerId ->
            ( { model | blackPlayerId = blackPlayerId }, Effect.none )


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
      }
    , Effect.fromCmd replayDownloadCmd
    )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
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
    [ grayBox
        [ heading T.adminUserAssignmentPageTitle
        , textParagraph T.adminUserAssignmentL1
        ]
    , grayBox
        [ Input.text []
            { onChange = TypeUpdateGameId
            , text = model.gameIdRaw
            , placeholder = Just (Input.placeholder [] (Element.text T.enterMatchId))
            , label = Input.labelHidden T.matchId
            }
            |> el [ padding 10 ]
        , model.replay
            |> Maybe.map (\replay -> gamePreview shared model replay)
            |> Maybe.withDefault Element.none
        ]
    ]


gamePreview : Shared.Model -> Model -> Replay -> Element Msg
gamePreview shared model replay =
    column []
        [ heading replay.key
        , replay.blackPlayer
            |> Maybe.map playerLabel
            |> Maybe.withDefault (playerInput model.blackPlayerId TypeUpdateBlackPlayerId)
        , gamePreviewImage shared (Debug.log "replay" replay)
        , replay.whitePlayer
            |> Maybe.map playerLabel
            |> Maybe.withDefault (playerInput model.whitePlayerId TypeUpdateWhitePlayerId)
        ]


playerInput : String -> (String -> Msg) -> Element Msg
playerInput inputText onChange =
    row []
        [ Input.text [ padding 10 ]
            { onChange = onChange
            , text = inputText
            , placeholder = Just (Input.placeholder [] (Element.text T.adminUserAssignmentEnterId))
            , label = Input.labelHidden T.adminUserAssignmentEnterId
            }
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
            Sako.initialPosition |> Sako.doActionsList actionHistory
    in
    position
        |> Maybe.map (PositionView.renderStatic WhiteBottom)
        |> Maybe.map (PositionView.viewStatic (PositionView.staticViewConfig shared.colorConfig))
        |> Maybe.map (Element.el [ width (px 400), height (px 400) ])
        |> Maybe.withDefault Element.none
