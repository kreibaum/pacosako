module Shared exposing
    ( Flags
    , Model
    , Msg(..)
    , User
    , collapseHeader
    , init
    , subscriptions
    , update
    )

import Api.Backend
import Api.LocalStorage as LocalStorage exposing (CustomTimer, Permission(..))
import Api.Ports
import Api.Websocket exposing (WebsocketConnectionState)
import Browser.Events
import Browser.Navigation exposing (Key)
import Colors exposing (ColorConfig)
import Http
import Json.Decode as Decode exposing (Decoder, Value)
import Json.Encode exposing (Value)
import List.Extra as List
import Request exposing (Request)
import Time exposing (Posix)
import Translations exposing (Language(..))
import Url exposing (Url)


type alias Flags =
    Value


type alias Model =
    { url : Url
    , key : Key
    , windowSize : ( Int, Int )
    , user : Maybe User

    -- Even when not logged in, you can set a username that is shown to other
    -- people sharing a game with you.
    , username : String
    , recentCustomTimes : List CustomTimer
    , playSounds : Bool
    , permissions : List LocalStorage.Permission
    , now : Posix
    , oAuthState : String
    , isHeaderOpen : Bool
    , websocketConnectionState : WebsocketConnectionState
    , lastWebsocketStatusUpdate : Posix
    , colorConfig : ColorConfig
    }


collapseHeader : Model -> Model
collapseHeader model =
    { model | isHeaderOpen = False }


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
    | SetPlaySounds Bool
    | SetColorConfig ColorConfig
    | WindowResize Int Int
    | UpdateNow Posix
    | AddRecentCustomTimer CustomTimer
    | SetHeaderOpen Bool
    | WebsocketStatusChange WebsocketConnectionState


init : Request -> Flags -> ( Model, Cmd Msg )
init { url, key } flags =
    let
        ls =
            LocalStorage.load flags

        oAuthState =
            Decode.decodeValue (Decode.field "oAuthState" Decode.string) flags
                |> Result.toMaybe
                |> Maybe.withDefault ""

        now =
            parseNow flags
    in
    ( { url = url
      , key = key
      , windowSize = parseWindowSize flags
      , user = Nothing
      , username = ls.data.username
      , recentCustomTimes = ls.data.recentCustomTimes
      , permissions = ls.permissions
      , playSounds = ls.data.playSounds
      , now = now
      , oAuthState = oAuthState
      , isHeaderOpen = False
      , websocketConnectionState = Api.Websocket.WebsocketConnecting
      , lastWebsocketStatusUpdate = now
      , colorConfig = ls.data.colorConfig
      }
    , Cmd.none
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

        SetPlaySounds playSounds ->
            setPlaySound playSounds model

        SetColorConfig colorConfig ->
            setColorConfig colorConfig model

        WindowResize width height ->
            ( { model | windowSize = ( width, height ) }, Cmd.none )

        UpdateNow now ->
            ( { model | now = now }, Cmd.none )

        TriggerReload ->
            ( model, Browser.Navigation.reload )

        AddRecentCustomTimer data ->
            addRecentCustomTimer data model

        SetHeaderOpen state ->
            ( { model | isHeaderOpen = state }, Cmd.none )

        WebsocketStatusChange state ->
            ( { model | websocketConnectionState = state, lastWebsocketStatusUpdate = model.now }, Cmd.none )


{-| Adds a custom timer to the history and trigges a "save to local storage" event.
-}
addRecentCustomTimer : CustomTimer -> Model -> ( Model, Cmd Msg )
addRecentCustomTimer data model =
    let
        newModel =
            { model | recentCustomTimes = addTimerToList data model.recentCustomTimes }
    in
    ( newModel, triggerSaveLocalStorage newModel )


{-| Takes a custom timer and adds it to a list of timers. If it is already in
this list, it is pulled to the front. If the list contains more than two entries,
old entries are dropped.
-}
addTimerToList : CustomTimer -> List CustomTimer -> List CustomTimer
addTimerToList data oldList =
    (data :: oldList)
        |> List.unique
        |> List.take 2


setLanguage : Language -> Model -> ( Model, Cmd Msg )
setLanguage lang model =
    ( model
    , Api.Backend.postLanguage lang HttpError (\() -> TriggerReload)
    )


setPlaySound : Bool -> Model -> ( Model, Cmd Msg )
setPlaySound playSounds model =
    let
        newModel =
            { model | playSounds = playSounds }
    in
    ( newModel, triggerSaveLocalStorage newModel )


setColorConfig : ColorConfig -> Model -> ( Model, Cmd Msg )
setColorConfig colorConfig model =
    let
        newModel =
            { model | colorConfig = colorConfig }
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
        { data = { username = model.username, recentCustomTimes = model.recentCustomTimes, playSounds = model.playSounds, colorConfig = model.colorConfig }
        , permissions = model.permissions
        }


subscriptions : Request -> Model -> Sub Msg
subscriptions _ _ =
    Sub.batch
        [ LocalStorage.subscribeSave TriggerSaveLocalStorage
        , Browser.Events.onResize WindowResize
        , Api.Websocket.listenToStatus WebsocketStatusChange
        , Time.every 1000 UpdateNow
        ]
