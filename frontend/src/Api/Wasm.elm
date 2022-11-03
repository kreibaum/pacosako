port module Api.Wasm exposing (RpcCall(..), RpcResponse(..), rpcCall, rpcRespone)

{-| This module exposes the RPC required to interact with the pacosako library
which has been compiled to wasm. All calls are async.
-}

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
    = HistoryToReplayNotation { board_fen : String, action_history : List Action }
    | LegalAction { board_fen : String, action_history : List Action }
    | RandomPosition Int


{-| The message received from the wasm worker
-}
type RpcResponse
    = HistoryToReplayNotationResponse (List HalfMove)
    | LegalActionResponse (List Action)
    | RandomPositionResponse String
    | RpcError String


encodeObjectWithOneKey : String -> Value -> Value
encodeObjectWithOneKey key value =
    Encode.object [ ( key, value ) ]


encodeRpcCall : RpcCall -> Value
encodeRpcCall msg =
    case msg of
        HistoryToReplayNotation { board_fen, action_history } ->
            Encode.object
                [ ( "board_fen", Encode.string board_fen )
                , ( "action_history", Encode.list Sako.encodeAction action_history )
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


decodeHistoryToReplayNotationResponse : Decoder RpcResponse
decodeHistoryToReplayNotationResponse =
    Decode.map HistoryToReplayNotationResponse
        (Decode.field "HistoryToReplayNotation"
            (Decode.field "notation" (Decode.list decodeHalfMove))
        )


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


decodeRpcError : Decoder RpcResponse
decodeRpcError =
    Decode.map RpcError (Decode.field "RpcError" Decode.string)


decodeRpcCall : Decoder RpcResponse
decodeRpcCall =
    Decode.oneOf
        [ decodeHistoryToReplayNotationResponse
        , decodeLegalActionResponse
        , decodeRandomPositionResponse
        , decodeRpcError
        ]


{-| Tries to decode the Value. If that does not work, reports the error as RpcError.
-}
runRpcCallDecoder : Value -> RpcResponse
runRpcCallDecoder value =
    Decode.decodeValue decodeRpcCall value
        |> Result.extract (RpcError << Decode.errorToString)
