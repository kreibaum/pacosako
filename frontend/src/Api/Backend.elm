module Api.Backend exposing
    ( Api
    , PagedGames
    , Replay
    , checkGameExists
    , describeError
    , getCurrentLogin
    , getJson
    , getLogout
    , getMyGames
    , getPublicUserData
    , getRecentGameKeys
    , getReplay
    , postJson
    , postLanguage
    , postLoginPassword
    , postMatchRequest
    , postRematchFromActionIndex
    , postSave
    )

{-| Server API. This is a mixed bag of all the GET and POST calls we can make to
the server api.
-}

import Api.Decoders exposing (CompressedMatchState, ControlLevel, PublicUserData, decodeCompressedMatchState, decodeControlLevel, decodePublicUserData)
import Http exposing (Error)
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline exposing (required)
import Json.Encode as Encode exposing (Value)
import Result.Extra as Result
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

                    Spanish ->
                        "es"
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
-- Handling Landing Page -------------------------------------------------------
--------------------------------------------------------------------------------


{-| GET a list of all recently creates games.
-}
getRecentGameKeys : Api (List CompressedMatchState) msg
getRecentGameKeys =
    getJson
        { url = "/api/game/recent"
        , decoder =
            Decode.list decodeCompressedMatchState
                |> Decode.map List.reverse
        }


type alias MatchParameters =
    { timer : Maybe Timer.TimerConfig
    , safeMode : Bool
    , drawAfterNRepetitions : Int
    , aiSideRequest : Maybe AiSideRequestParameters
    }


type alias AiSideRequestParameters =
    { modelName : String
    , modelStrength : Int
    , modelTemperature : Float
    , color : Maybe Sako.Color
    }


{-| Send a HEAD request to /api/game/:key and check the return code.
Only 200 is ok.
-}
checkGameExists : String -> Api Bool msg
checkGameExists key _ successHandler =
    Http.request
        { method = "HEAD"
        , headers = []
        , url = "/api/game/" ++ key
        , body = Http.emptyBody
        , expect = Http.expectWhatever (Result.isOk >> successHandler)
        , timeout = Nothing
        , tracker = Nothing
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
        , ( "ai_side_request", Maybe.map encodeAiSideRequest record.aiSideRequest |> Maybe.withDefault Encode.null )
        ]


encodeAiSideRequest : AiSideRequestParameters -> Value
encodeAiSideRequest record =
    Encode.object
        [ ( "model_name", Encode.string record.modelName )
        , ( "model_strength", Encode.int record.modelStrength )
        , ( "model_temperature", Encode.float record.modelTemperature )
        , ( "color", Maybe.map Sako.encodeColor record.color |> Maybe.withDefault Encode.null )
        ]



--------------------------------------------------------------------------------
-- Replay Page -----------------------------------------------------------------
--------------------------------------------------------------------------------


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


getReplay : String -> Api Replay msg
getReplay key =
    getJson
        { url = "/api/game/" ++ key
        , decoder = decodeReplay
        }


type alias Replay =
    { key : String
    , actions : List ( Sako.Action, Posix )
    , timer : Maybe Timer.Timer
    , victoryState : Sako.VictoryState
    , setupOptions : Sako.SetupOptions
    , whitePlayer : Maybe PublicUserData
    , blackPlayer : Maybe PublicUserData
    , whiteControl : ControlLevel
    , blackControl : ControlLevel
    }


decodeReplay : Decoder Replay
decodeReplay =
    Decode.succeed Replay
        |> required "key" Decode.string
        |> required "actions" (Decode.list decodeStampedAction)
        |> required "timer" (Decode.maybe Timer.decodeTimer)
        |> required "victory_state" Sako.decodeVictoryState
        |> required "setup_options" Sako.decodeSetupOptions
        |> required "white_player" (Decode.nullable decodePublicUserData)
        |> required "black_player" (Decode.nullable decodePublicUserData)
        |> required "white_control" decodeControlLevel
        |> required "black_control" decodeControlLevel


decodeStampedAction : Decoder ( Sako.Action, Posix )
decodeStampedAction =
    Decode.map2 (\a b -> ( a, b ))
        Sako.decodeAction
        (Decode.field "timestamp" Iso8601.decoder)



--------------------------------------------------------------------------------
-- Me Page and My Games Page ---------------------------------------------------
--------------------------------------------------------------------------------
-- /api/me/games?offset=..&limit=..


type alias PagedGames =
    { games : List CompressedMatchState
    , totalGames : Int
    }


getMyGames : { offset : Int, limit : Int } -> Api PagedGames msg
getMyGames { offset, limit } =
    getJson
        { url = "/api/me/games?offset=" ++ String.fromInt offset ++ "&limit=" ++ String.fromInt limit
        , decoder =
            Decode.map2 PagedGames
                (Decode.field "games" (Decode.list decodeCompressedMatchState))
                (Decode.field "total_games" Decode.int)
        }



--------------------------------------------------------------------------------
-- Public User Data ------------------------------------------------------------
--------------------------------------------------------------------------------


getPublicUserData : Int -> Api PublicUserData msg
getPublicUserData userId =
    getJson
        { url = "/api/user/" ++ String.fromInt userId
        , decoder = decodePublicUserData
        }
