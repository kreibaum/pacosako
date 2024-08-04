module Shared exposing
    ( Flags
    , Model
    , Msg(..)
    , collapseHeader
    , init
    , isRolf
    , subscriptions
    , update
    )

import Ai exposing (AiState)
import Api.Backend
import Api.LocalStorage as LocalStorage exposing (CustomTimer, Permission(..))
import Api.Ports
import Api.Websocket exposing (WebsocketConnectionState)
import Browser.Events
import Browser.Navigation exposing (Key)
import Colors exposing (ColorConfig)
import Http
import Json.Decode as Decode exposing (Decoder, Value)
import List.Extra as List
import Request exposing (Request)
import Time exposing (Posix)
import Translations exposing (Language(..))
import User


type alias Flags =
    Value


type alias Model =
    { key : Key
    , windowSize : ( Int, Int )
    , recentCustomTimes : List CustomTimer
    , playSounds : Bool
    , permissions : List LocalStorage.Permission
    , now : Posix
    , loggedInUser : Maybe User.LoggedInUserData
    , isHeaderOpen : Bool
    , websocketConnectionState : WebsocketConnectionState
    , lastWebsocketStatusUpdate : Posix
    , colorConfig : ColorConfig

    -- As the AI is managed by the WebWorker, it is Shared state.
    , aiState : AiState
    }


collapseHeader : Model -> Model
collapseHeader model =
    { model | isHeaderOpen = False }


type Msg
    = TriggerSaveLocalStorage
    | TriggerReload
    | HttpError Http.Error
    | StringError String
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
    | NavigateTo String
    | SetAiState Ai.AiState


init : Request -> Flags -> ( Model, Cmd Msg )
init { key } flags =
    let
        ls =
            LocalStorage.load flags

        now =
            parseNow flags
    in
    ( { key = key
      , windowSize = parseWindowSize flags
      , recentCustomTimes = ls.data.recentCustomTimes
      , permissions = ls.permissions
      , playSounds = ls.data.playSounds
      , now = now
      , loggedInUser = User.parseLoggedInUser flags
      , isHeaderOpen = False
      , websocketConnectionState = Api.Websocket.WebsocketConnecting
      , lastWebsocketStatusUpdate = now
      , colorConfig = ls.data.colorConfig
      , aiState = Ai.initAiState
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

        StringError errorString ->
            ( model, Api.Ports.logToConsole errorString )

        LogoutSuccess ->
            ( model, Cmd.none )

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

        NavigateTo target ->
            ( model, Browser.Navigation.load target )

        SetAiState aiState ->
            ( { model | aiState = aiState }, Cmd.none )


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
        { data = { recentCustomTimes = model.recentCustomTimes, playSounds = model.playSounds, colorConfig = model.colorConfig }
        , permissions = model.permissions
        }


subscriptions : Request -> Model -> Sub Msg
subscriptions _ _ =
    Sub.batch
        [ LocalStorage.subscribeSave TriggerSaveLocalStorage
        , Browser.Events.onResize WindowResize
        , Api.Websocket.listenToStatus WebsocketStatusChange
        , Time.every 1000 UpdateNow
        , Ai.aiStateSub StringError SetAiState
        ]


{-| Utitilty function to check if the user with id 1 is logged in. As a solo
development project, this is a useful way to roll out partially done features
to myself only.
-}
isRolf : Model -> Bool
isRolf model =
    case model.loggedInUser of
        Just user ->
            user.userId == 1

        Nothing ->
            False
