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
import Api.LocalStorage as LocalStorage
import Api.Ports
import Browser.Navigation exposing (Key, pushUrl)
import Custom.Element exposing (icon)
import Element exposing (..)
import Element.Background as Background
import Element.Font as Font
import Element.Input as Input
import FontAwesome.Regular as Regular
import FontAwesome.Solid as Solid
import FontAwesome.Styles
import Http
import I18n.Strings as I18n exposing (Language)
import Json.Decode as Decode exposing (Decoder, Value, bool)
import Json.Encode as Encode exposing (Value)
import Spa.Document exposing (Document)
import Spa.Generated.Route as Route exposing (Route)
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
    Decode.map2 (\x y -> ( x, y ))
        (Decode.field "width" Decode.int)
        (Decode.field "height" Decode.int)



-- UPDATE


type Msg
    = TriggerSaveLocalStorage
    | HttpError Http.Error
    | LoginSuccess User
    | LogoutSuccess


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


triggerSaveLocalStorage : Model -> Cmd msg
triggerSaveLocalStorage model =
    LocalStorage.store
        { data = { username = model.username, language = model.language }
        , permissions = model.permissions
        }


subscriptions : Model -> Sub Msg
subscriptions model =
    LocalStorage.subscribeSave TriggerSaveLocalStorage



-- VIEW


view :
    { page : Document msg, toMsg : Msg -> msg }
    -> Model
    -> Document msg
view { page, toMsg } model =
    { title = page.title
    , body =
        [ Element.column [ width fill, height fill, Element.scrollbarY ]
            ([ Element.html FontAwesome.Styles.css
             , pageHeader model Element.none
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
        [ pageHeaderButton Route.Top "Play Paco Ŝako"
        , pageHeaderButton Route.Editor "Design Puzzles"
        , pageHeaderButton Route.Tutorial "Tutorial"
        , additionalHeader
        , loginHeaderInfo model.user
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


loginHeaderInfo : Maybe User -> Element Msg
loginHeaderInfo login =
    let
        loginCaption =
            case login of
                Just user ->
                    Element.row [ padding 10, spacing 10 ] [ icon [] Solid.user, Element.text user.username ]

                Nothing ->
                    Element.row [ padding 10, spacing 10 ] [ icon [] Solid.signInAlt, Element.text "Login" ]
    in
    Element.link [ Element.alignRight ]
        { url = Route.toString Route.Login
        , label = loginCaption
        }


backgroundFocus : Bool -> List (Element.Attribute msg)
backgroundFocus isFocused =
    if isFocused then
        [ Background.color (Element.rgb255 200 200 200) ]

    else
        []
