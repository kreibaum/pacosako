module Shared exposing
    ( Flags
    , Model
    , Msg
    , User
    , init
    , subscriptions
    , update
    , view
    )

import Api.Backend
import Api.LocalStorage as LocalStorage exposing (Permission(..))
import Api.Ports
import Browser.Dom
import Browser.Events
import Browser.Navigation exposing (Key)
import Custom.Element exposing (icon)
import Element exposing (..)
import Element.Background as Background
import Element.Input as Input
import FontAwesome.Solid as Solid
import FontAwesome.Styles
import Http
import I18n.Strings as I18n exposing (I18nToken(..), Language(..), t)
import Json.Decode as Decode exposing (Decoder, Value)
import Json.Encode exposing (Value)
import Spa.Document exposing (Document)
import Spa.Generated.Route as Route exposing (Route)
import Svg.Custom
import Time exposing (Posix)
import Url exposing (Url)



-- INIT


type alias Flags =
    Value


type alias Model =
    { url : Url
    , key : Key
    , windowSize : ( Int, Int )
    , user : Maybe User
    , language : Language

    -- Even when not logged in, you can set a username that is shown to other
    -- people sharing a game with you.
    , username : String
    , permissions : List LocalStorage.Permission
    , now : Posix
    }


init : Flags -> Url -> Key -> ( Model, Cmd Msg )
init flags url key =
    let
        ls =
            LocalStorage.load flags
    in
    ( { url = url
      , key = key
      , windowSize = parseWindowSize flags
      , user = Nothing
      , language = ls.data.language
      , username = ls.data.username
      , permissions = ls.permissions
      , now = parseNow flags
      }
    , Api.Backend.getCurrentLogin HttpError
        (Maybe.map LoginSuccess >> Maybe.withDefault LogoutSuccess)
    )


parseWindowSize : Value -> ( Int, Int )
parseWindowSize value =
    Decode.decodeValue sizeDecoder value
        |> Result.withDefault ( 100, 100 )


sizeDecoder : Decoder ( Int, Int )
sizeDecoder =
    Decode.field "windowSize"
        (Decode.map2 (\x y -> ( x, y ))
            (Decode.field "width" Decode.int)
            (Decode.field "height" Decode.int)
        )


parseNow : Value -> Posix
parseNow value =
    let
        nowDecoder =
            Decode.map Time.millisToPosix
                (Decode.field "now" Decode.int)
    in
    Decode.decodeValue nowDecoder value
        |> Result.withDefault (Time.millisToPosix 0)



-- UPDATE


type Msg
    = TriggerSaveLocalStorage
    | HttpError Http.Error
    | LoginSuccess User
    | LogoutSuccess
    | UserHidesGamesArePublicHint
    | SetLanguage Language
    | WindowResize Int Int
    | UpdateNow Posix


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        TriggerSaveLocalStorage ->
            ( model, triggerSaveLocalStorage model )

        HttpError error ->
            ( model, Api.Ports.logToConsole (Api.Backend.describeError error) )

        LoginSuccess user ->
            ( { model | user = Just user }, Cmd.none )

        LogoutSuccess ->
            ( { model | user = Nothing }, Cmd.none )

        UserHidesGamesArePublicHint ->
            userHidesGamesArePublicHint model

        SetLanguage lang ->
            setLanguage lang model

        WindowResize width height ->
            ( { model | windowSize = ( width, height ) }, Cmd.none )

        UpdateNow now ->
            ( { model | now = now }, Cmd.none )


setLanguage : Language -> Model -> ( Model, Cmd Msg )
setLanguage lang model =
    let
        newModel =
            { model | language = lang }
    in
    ( newModel, triggerSaveLocalStorage newModel )


userHidesGamesArePublicHint : Model -> ( Model, Cmd Msg )
userHidesGamesArePublicHint model =
    let
        newModel =
            { model | permissions = HideGamesArePublicHint :: model.permissions }
    in
    ( newModel, triggerSaveLocalStorage newModel )


triggerSaveLocalStorage : Model -> Cmd msg
triggerSaveLocalStorage model =
    LocalStorage.store
        { data = { username = model.username, language = model.language }
        , permissions = model.permissions
        }


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ LocalStorage.subscribeSave TriggerSaveLocalStorage
        , Browser.Events.onResize WindowResize
        , Time.every 1000 UpdateNow
        ]



-- VIEW


view :
    { page : Document msg, toMsg : Msg -> msg }
    -> Model
    -> Document msg
view { page, toMsg } model =
    { title = page.title
    , body =
        [ Element.html FontAwesome.Styles.css
        , Element.column [ width fill, height fill, Element.scrollbarY ]
            ([ pageHeader model Element.none
                |> Element.map toMsg
             , gamesArePublicHint model
                |> Element.map toMsg
             ]
                ++ page.body
            )
        ]
    }


{-| Header that is shared by all pages.
-}
pageHeader : Model -> Element Msg -> Element Msg
pageHeader model additionalHeader =
    Element.row [ width fill, Background.color (Element.rgb255 230 230 230) ]
        [ pageHeaderButton Route.Top (t model.language i18nPlayPacoSako)
        , pageHeaderButton Route.Editor (t model.language i18nDesignPuzzles)
        , pageHeaderButton Route.Tutorial (t model.language i18nTutorial)
        , additionalHeader
        , languageChoice

        -- login header is disabled, until we get proper registration (oauth)
        --, loginHeaderInfo model model.user
        ]


pageHeaderButton : Route -> String -> Element Msg
pageHeaderButton route caption =
    Element.link [ padding 10 ]
        { url = Route.toString route
        , label = Element.text caption
        }


type alias User =
    { id : Int
    , username : String
    }


loginHeaderInfo : Model -> Maybe User -> Element Msg
loginHeaderInfo model login =
    let
        loginCaption =
            case login of
                Just user ->
                    Element.row [ padding 10, spacing 10 ] [ icon [] Solid.user, Element.text user.username ]

                Nothing ->
                    Element.row [ padding 10, spacing 10 ] [ icon [] Solid.signInAlt, Element.text (t model.language i18nLogin) ]
    in
    Element.link [ Element.alignRight ]
        { url = Route.toString Route.Login
        , label = loginCaption
        }


gamesArePublicHint : Model -> Element Msg
gamesArePublicHint model =
    if List.member HideGamesArePublicHint model.permissions then
        Element.none

    else
        Element.row [ width fill, Background.color (Element.rgb255 255 230 230), padding 10 ]
            [ paragraph [ spacing 10 ]
                [ Element.text (t model.language I18n.gamesArePublicHint)
                , Input.button
                    [ Element.alignRight ]
                    { onPress = Just UserHidesGamesArePublicHint
                    , label = Element.text (t model.language I18n.hideGamesArePublicHint)
                    }
                ]
            ]


{-| Allows the user to choose the ui language.
-}
languageChoice : Element Msg
languageChoice =
    Element.row [ Element.alignRight ]
        [ Input.button [ padding 2 ]
            { onPress = Just (SetLanguage English)
            , label = Svg.Custom.flagEn |> Element.html
            }
        , Input.button [ padding 2 ]
            { onPress = Just (SetLanguage Dutch)
            , label = Svg.Custom.flagNl |> Element.html
            }
        , Input.button [ padding 2 ]
            { onPress = Just (SetLanguage Esperanto)
            , label = Svg.Custom.flagEo |> Element.html
            }
        ]



--------------------------------------------------------------------------------
-- I18n Strings ----------------------------------------------------------------
--------------------------------------------------------------------------------


i18nPlayPacoSako : I18nToken String
i18nPlayPacoSako =
    I18nToken
        { english = "Play Paco Ŝako"
        , dutch = "Speel Paco Ŝako"
        , esperanto = "Ludi Paco Ŝako"
        }


i18nDesignPuzzles : I18nToken String
i18nDesignPuzzles =
    I18nToken
        { english = "Design Puzzles"
        , dutch = "Ontwerp puzzel"
        , esperanto = "Desegni Puzloj"
        }


i18nTutorial : I18nToken String
i18nTutorial =
    I18nToken
        { english = "Tutorial"
        , dutch = "Tutorial"
        , esperanto = "Lernilo"
        }


i18nLogin : I18nToken String
i18nLogin =
    I18nToken
        { english = "Login"
        , dutch = "Log in"
        , esperanto = "Ensaluti"
        }
