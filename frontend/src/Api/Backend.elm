module Api.Backend exposing
    ( Api
    , DiscordApplicationId(..)
    , Replay
    , SetupOptions
    , describeError
    , encodeSetupOptions
    , getCurrentLogin
    , getDiscordApplicationId
    , getLogout
    , getRecentGameKeys
    , getReplay
    , postLanguage
    , postLoginPassword
    , postMatchRequest
    , postRematchFromActionIndex
    , postSave
    )

{-| Server API. This is a mixed bag of all the GET and POST calls we can make to
the server api.
-}

import Api.Decoders exposing (CurrentMatchState, decodeMatchState)
import Http exposing (Error)
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import Sako
import SaveState exposing (SaveState(..), saveStateId)
import Time exposing (Posix)
import Timer
import Translations exposing (Language(..))


{-| When calling a server method, you need to specify how errors are handled and
what wou want to do with the payload when it arrives. This types alias makes the
type signatures of Api calls much cleaner.
-}
type alias Api a msg =
    (Error -> msg) -> (a -> msg) -> Cmd msg


describeError : Error -> String
describeError error =
    case error of
        Http.BadUrl url ->
            "Bad url: " ++ url

        Http.Timeout ->
            "Timeout error."

        Http.NetworkError ->
            "Network error."

        Http.BadStatus statusCode ->
            "Bad status: " ++ String.fromInt statusCode

        Http.BadBody body ->
            "Bad body: " ++ body


{-| Internal helper function to POST to HTTP Apis with Json data.

This takes care of getting the error message handler and the ok message handler
in the right place so individual APIs don't need to mention those.

-}
postJson : { url : String, body : Value, decoder : Decoder a } -> Api a msg
postJson config errMsg okMsg =
    Http.post
        { url = config.url
        , body = Http.jsonBody config.body
        , expect = Http.expectJson (handle errMsg okMsg) config.decoder
        }


{-| Internal helper function to GET from HTTP Apis with Json data.

This takes care of getting the error message handler and the ok message handler
in the right place so individual APIs don't need to mention those.

-}
getJson : { url : String, decoder : Decoder a } -> Api a msg
getJson config errMsg okMsg =
    Http.get
        { url = config.url
        , expect = Http.expectJson (handle errMsg okMsg) config.decoder
        }


handle : (Error -> msg) -> (a -> msg) -> Result Error a -> msg
handle errMsg okMsg result =
    case result of
        Ok ok ->
            okMsg ok

        Err err ->
            errMsg err



--------------------------------------------------------------------------------
-- Handling internationalisation -----------------------------------------------
--------------------------------------------------------------------------------


postLanguage : Language -> Api () msg
postLanguage lang errMsg okMsg =
    Http.post
        { url = "/api/language"
        , body =
            Http.stringBody "text/plain"
                (case lang of
                    English ->
                        "en"

                    Dutch ->
                        "nl"

                    Esperanto ->
                        "eo"

                    German ->
                        "de"

                    Swedish ->
                        "sv"
                )
        , expect = Http.expectWhatever (handle errMsg okMsg)
        }



--------------------------------------------------------------------------------
-- Handling authentication -----------------------------------------------------
--------------------------------------------------------------------------------


type alias LoginData =
    { username : String
    , password : String
    }


type alias User =
    { id : Int
    , username : String
    }


encodeLoginData : LoginData -> Value
encodeLoginData record =
    Encode.object
        [ ( "username", Encode.string <| record.username )
        , ( "password", Encode.string <| record.password )
        ]


decodeUser : Decoder User
decodeUser =
    Decode.map2 User
        (Decode.field "user_id" Decode.int)
        (Decode.field "username" Decode.string)


postLoginPassword : LoginData -> Api User msg
postLoginPassword data =
    postJson
        { url = "/api/login/password"
        , body = encodeLoginData data
        , decoder = decodeUser
        }


getCurrentLogin : Api (Maybe User) msg
getCurrentLogin =
    getJson
        { url = "/api/user_id"
        , decoder = Decode.maybe decodeUser
        }


getLogout : Api () msg
getLogout =
    getJson
        { url = "/api/logout"
        , decoder = Decode.succeed ()
        }



--------------------------------------------------------------------------------
-- Handling Editor Persistence -------------------------------------------------
--------------------------------------------------------------------------------


type alias SavePositionDone =
    { id : Int
    }


postSave : Sako.Position -> SaveState -> Api SavePositionDone msg
postSave position saveState =
    case saveStateId saveState of
        Just id ->
            postSaveUpdate position id

        Nothing ->
            postSaveCreate position


decodeSavePositionDone : Decoder SavePositionDone
decodeSavePositionDone =
    Decode.map SavePositionDone
        (Decode.field "id" Decode.int)


postSaveCreate : Sako.Position -> Api SavePositionDone msg
postSaveCreate position =
    postJson
        { url = "/api/position"
        , body = encodeCreatePosition position
        , decoder = decodeSavePositionDone
        }


postSaveUpdate : Sako.Position -> Int -> Api SavePositionDone msg
postSaveUpdate position id =
    postJson
        { url = "/api/position/" ++ String.fromInt id
        , body = encodeCreatePosition position
        , decoder = decodeSavePositionDone
        }


{-| The server treats this object as an opaque JSON object.
-}
type alias CreatePositionData =
    { notation : String
    }


encodeCreatePositionData : CreatePositionData -> Value
encodeCreatePositionData record =
    Encode.object
        [ ( "notation", Encode.string <| record.notation )
        ]


encodeCreatePosition : Sako.Position -> Value
encodeCreatePosition position =
    Encode.object
        [ ( "data"
          , encodeCreatePositionData
                { notation = Sako.exportExchangeNotation position
                }
          )
        ]



--------------------------------------------------------------------------------
-- Handling Play Page ----------------------------------------------------------
--------------------------------------------------------------------------------


{-| GET a list of all recently creates games.
-}
getRecentGameKeys : Api (List CurrentMatchState) msg
getRecentGameKeys =
    getJson
        { url = "/api/game/recent"
        , decoder =
            Decode.list decodeMatchState
                |> Decode.map List.reverse
        }


type alias MatchParameters =
    { timer : Maybe Timer.TimerConfig
    , safeMode : Bool
    , drawAfterNRepetitions : Int
    }


{-| Use this to call the "create game" api of the server.
-}
postMatchRequest : MatchParameters -> Api String msg
postMatchRequest config errorHandler successHandler =
    Http.post
        { url = "/api/create_game"
        , body = Http.jsonBody (encodeMatchParameters config)
        , expect =
            Http.expectString
                (\response ->
                    case response of
                        Ok key ->
                            successHandler key

                        Err e ->
                            errorHandler e
                )
        }


encodeMatchParameters : MatchParameters -> Value
encodeMatchParameters record =
    Encode.object
        [ ( "timer"
          , Maybe.map Timer.encodeConfig record.timer
                |> Maybe.withDefault Encode.null
          )
        , ( "safe_mode", Encode.bool record.safeMode )
        , ( "draw_after_n_repetitions", Encode.int record.drawAfterNRepetitions )
        ]


postRematchFromActionIndex : String -> Int -> Maybe Timer.TimerConfig -> Api String msg
postRematchFromActionIndex sourceKey actionIndex config errorHandler successHandler =
    Http.post
        { url = "/api/branch_game"
        , body = Http.jsonBody (encodeBranchParameters sourceKey actionIndex config)
        , expect =
            Http.expectString
                (\response ->
                    case response of
                        Ok key ->
                            successHandler key

                        Err e ->
                            errorHandler e
                )
        }


encodeBranchParameters : String -> Int -> Maybe Timer.TimerConfig -> Value
encodeBranchParameters key actionIndex config =
    Encode.object
        [ ( "source_key", Encode.string key )
        , ( "action_index", Encode.int actionIndex )
        , ( "timer"
          , Maybe.map Timer.encodeConfig config
                |> Maybe.withDefault Encode.null
          )
        ]



--------------------------------------------------------------------------------
-- Replay Page -----------------------------------------------------------------
--------------------------------------------------------------------------------


getReplay : String -> Api Replay msg
getReplay key =
    getJson
        { url = "/api/game/" ++ key
        , decoder = decodeReplay
        }


type alias Replay =
    { actions : List ( Sako.Action, Posix )
    , timer : Maybe Timer.Timer
    , victoryState : Sako.VictoryState
    , setupOptions : SetupOptions
    }


decodeReplay : Decoder Replay
decodeReplay =
    Decode.map4 Replay
        (Decode.field "actions" (Decode.list decodeStampedAction))
        (Decode.field "timer" (Decode.maybe Timer.decodeTimer))
        (Decode.field "victory_state" Sako.decodeVictoryState)
        (Decode.field "setup_options" decodeSetupOptions)


decodeStampedAction : Decoder ( Sako.Action, Posix )
decodeStampedAction =
    Decode.map2 (\a b -> ( a, b ))
        Sako.decodeAction
        (Decode.field "timestamp" Iso8601.decoder)


type alias SetupOptions =
    { safe_mode : Bool
    , draw_after_n_repetitions : Int
    }


encodeSetupOptions : SetupOptions -> Value
encodeSetupOptions options =
    Encode.object
        [ ( "safe_mode", Encode.bool options.safe_mode )
        , ( "draw_after_n_repetitions", Encode.int options.draw_after_n_repetitions )
        ]


decodeSetupOptions : Decoder SetupOptions
decodeSetupOptions =
    Decode.map2 SetupOptions
        (Decode.field "safe_mode" Decode.bool)
        (Decode.field "draw_after_n_repetitions" Decode.int)



-- API methods for discord OAuth


type DiscordApplicationId
    = DiscordApplicationId String


getDiscordApplicationId : Api DiscordApplicationId msg
getDiscordApplicationId =
    getJson
        { url = "/api/oauth/discord_client_id"
        , decoder = Decode.string |> Decode.map DiscordApplicationId
        }
