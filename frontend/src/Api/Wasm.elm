port module Api.Wasm exposing (ReplayData, RpcCall(..), RpcResponse(..), aiCall, aiResponse, rpcCall, rpcRespone)

{-| This module exposes the RPC required to interact with the pacosako library
which has been compiled to wasm. All calls are async.
-}

import Api.Backend
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import Notation exposing (HalfMove, decodeHalfMove)
import Result.Extra as Result
import Sako exposing (Action, decodeAction)


port rpcResponseValue : (Value -> msg) -> Sub msg


rpcRespone : (RpcResponse -> msg) -> Sub msg
rpcRespone msg =
    rpcResponseValue (\v -> msg (runRpcCallDecoder v))


port rpcCallValue : Value -> Cmd msg


rpcCall : RpcCall -> Cmd msg
rpcCall =
    encodeRpcCall >> rpcCallValue


{-| The message send to the wasm worker
-}
type RpcCall
    = HistoryToReplayNotation { board_fen : String, action_history : List Action, setup : Api.Backend.SetupOptions }
    | LegalAction { board_fen : String, action_history : List Action }
    | RandomPosition Int
    | AnalyzePosition { board_fen : String, action_history : List Action }


{-| The message received from the wasm worker
-}
type RpcResponse
    = HistoryToReplayNotationResponse ReplayData
    | LegalActionResponse (List Action)
    | RandomPositionResponse String
    | AnalyzePositionResponse { analysis : { text_summary : String } }
    | RpcError String


type alias ReplayData =
    { notation : List HalfMove, opening : String }


encodeObjectWithOneKey : String -> Value -> Value
encodeObjectWithOneKey key value =
    Encode.object [ ( key, value ) ]


encodeRpcCall : RpcCall -> Value
encodeRpcCall msg =
    case msg of
        HistoryToReplayNotation { board_fen, action_history, setup } ->
            Encode.object
                [ ( "board_fen", Encode.string board_fen )
                , ( "action_history", Encode.list Sako.encodeAction action_history )
                , ( "setup", Api.Backend.encodeSetupOptions setup )
                ]
                |> encodeObjectWithOneKey "HistoryToReplayNotation"

        LegalAction { board_fen, action_history } ->
            Encode.object
                [ ( "board_fen", Encode.string board_fen )
                , ( "action_history", Encode.list Sako.encodeAction action_history )
                ]
                |> encodeObjectWithOneKey "LegalActions"

        RandomPosition tries ->
            Encode.object [ ( "tries", Encode.int tries ) ]
                |> encodeObjectWithOneKey "RandomPosition"

        AnalyzePosition { board_fen, action_history } ->
            Encode.object
                [ ( "board_fen", Encode.string board_fen )
                , ( "action_history", Encode.list Sako.encodeAction action_history )
                ]
                |> encodeObjectWithOneKey "AnalyzePosition"


decodeHistoryToReplayNotationResponse : Decoder RpcResponse
decodeHistoryToReplayNotationResponse =
    Decode.map2 ReplayData
        (Decode.at [ "HistoryToReplayNotation", "notation" ] (Decode.list decodeHalfMove))
        (Decode.at [ "HistoryToReplayNotation", "opening" ] Decode.string)
        |> Decode.map HistoryToReplayNotationResponse


decodeLegalActionResponse : Decoder RpcResponse
decodeLegalActionResponse =
    Decode.map LegalActionResponse
        (Decode.field "LegalActions"
            (Decode.field "legal_actions" (Decode.list decodeAction))
        )


decodeRandomPositionResponse : Decoder RpcResponse
decodeRandomPositionResponse =
    Decode.map RandomPositionResponse
        (Decode.field "RandomPosition"
            (Decode.field "board_fen" Decode.string)
        )


decodeAnalyzePositionResponse : Decoder RpcResponse
decodeAnalyzePositionResponse =
    Decode.at [ "AnalyzePosition", "analysis", "text_summary" ] Decode.string
        |> Decode.map (\str -> AnalyzePositionResponse { analysis = { text_summary = str } })


decodeRpcError : Decoder RpcResponse
decodeRpcError =
    Decode.map RpcError (Decode.field "RpcError" Decode.string)


decodeRpcCall : Decoder RpcResponse
decodeRpcCall =
    Decode.oneOf
        [ decodeHistoryToReplayNotationResponse
        , decodeLegalActionResponse
        , decodeRandomPositionResponse
        , decodeAnalyzePositionResponse
        , decodeRpcError
        ]


{-| Tries to decode the Value. If that does not work, reports the error as RpcError.
-}
runRpcCallDecoder : Value -> RpcResponse
runRpcCallDecoder value =
    Decode.decodeValue decodeRpcCall value
        |> Result.extract (RpcError << Decode.errorToString)



--------------------------------------------------------------------------------
-- AI RPC, currently in a draft stage ------------------------------------------
--------------------------------------------------------------------------------
-- In: Vec<Action>, Out: Action


port aiResponseValue : (Value -> msg) -> Sub msg


aiResponse : (Action -> msg) -> msg -> Sub msg
aiResponse msg error =
    aiResponseValue (decodeActionIntoMsg msg error)


decodeActionIntoMsg : (Action -> msg) -> msg -> Value -> msg
decodeActionIntoMsg msg error value =
    Decode.decodeValue Sako.decodeAction value
        |> Result.map msg
        |> Result.withDefault error


port aiCallValue : Value -> Cmd msg


aiCall : List Action -> Cmd msg
aiCall actions =
    Encode.list Sako.encodeAction actions
        |> aiCallValue
