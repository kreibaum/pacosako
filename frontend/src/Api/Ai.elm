module Api.Ai exposing (AiWorkerState(..), requestMoveFromAi, subscribeMoveFromAi)

import Api.Ports as Ports
import Api.Websocket
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import Sako


type AiWorkerState
    = Starting
    | Running


fromStringAiWorkerState : String -> Decoder AiWorkerState
fromStringAiWorkerState string =
    case string of
        "Running" ->
            Decode.succeed Running

        "Starting" ->
            Decode.succeed Starting

        _ ->
            Decode.fail ("Not valid pattern for decoder to AiWorkerState. Pattern: " ++ string)


decodeAiWorkerState : Decoder AiWorkerState
decodeAiWorkerState =
    Decode.string |> Decode.andThen fromStringAiWorkerState


aiState : (AiWorkerState -> msg) -> Sub msg
aiState msg =
    Ports.aiState
        (\value ->
            Decode.decodeValue decodeAiWorkerState value
                |> Result.withDefault Starting
                |> msg
        )



-- {-| Restart the AI thread.
-- -}
-- port restartAiWorker : () -> Cmd msg


requestMoveFromAi : Cmd msg
requestMoveFromAi =
    Ports.requestMoveFromAi Encode.null


subscribeMoveFromAi : msg -> (Sako.Action -> msg) -> Sub msg
subscribeMoveFromAi errorMsg msg =
    Ports.subscribeMoveFromAi
        (\value ->
            Decode.decodeValue Sako.decodeAction value
                |> Result.map msg
                |> Result.withDefault errorMsg
        )
