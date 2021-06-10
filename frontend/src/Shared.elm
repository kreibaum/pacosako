module Shared exposing
    ( Flags
    , Model
    , Msg(..)
    , User
    , init
    , subscriptions
    , update
    )

import Api.Backend
import Api.LocalStorage as LocalStorage exposing (Permission(..))
import Api.Ports
import Browser.Events
import Browser.Navigation exposing (Key)
import Http
import I18n.Strings exposing (Language)
import Json.Decode as Decode exposing (Decoder, Value)
import Json.Encode exposing (Value)
import Request exposing (Request)
import Time exposing (Posix)
import Url exposing (Url)


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


type alias User =
    { id : Int
    , username : String
    }


type Msg
    = TriggerSaveLocalStorage
    | TriggerReload
    | HttpError Http.Error
    | LoginSuccess User
    | LogoutSuccess
    | UserHidesGamesArePublicHint
    | SetLanguage Language
    | WindowResize Int Int
    | UpdateNow Posix


init : Request -> Flags -> ( Model, Cmd Msg )
init { url, key } flags =
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


update : Request -> Msg -> Model -> ( Model, Cmd Msg )
update _ msg model =
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

        TriggerReload ->
            ( model, Browser.Navigation.reload )


setLanguage : Language -> Model -> ( Model, Cmd Msg )
setLanguage lang model =
    let
        newModel =
            { model | language = lang }
    in
    ( newModel
    , Cmd.batch
        [ triggerSaveLocalStorage newModel
        , Api.Backend.postLanguage lang HttpError (\() -> TriggerReload)
        ]
    )


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


subscriptions : Request -> Model -> Sub Msg
subscriptions _ _ =
    Sub.batch
        [ LocalStorage.subscribeSave TriggerSaveLocalStorage
        , Browser.Events.onResize WindowResize
        , Time.every 1000 UpdateNow
        ]
