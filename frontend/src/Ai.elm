module Ai exposing (AiInitProgress(..), AiState(..), aiStateSub, describeInitProgress, initAiState, startUpAi)

{-| We include Machine Learning based AI through ONNX files and use the javascript-side onnx-runtime to execute them.
We also have an opening book. This means a lot of things need to load (ideally from cache) before the AI is ready to play.
We need to add this as an explicit step before starting a game, so you don't start games without the AI being ready.
It also helps users understand if the AI is broken on their device. Otherwise the start is played by the opening book
and once the model takes over the game just stops.
-}

import Api.MessageGen
import Custom.Decode exposing (decodeConstant)
import Json.Decode
import Json.Encode
import Time exposing (Posix)


initAiState : AiState
initAiState =
    NotInitialized NotStarted


{-| Starts up the AI, if it not already starting. It is safe to call this
multiple times.
-}
startUpAi : Cmd a
startUpAi =
    Api.MessageGen.initAi Json.Encode.null


{-| The game page needs to understand if the AI is already running when processing new game states.
-}
type AiState
    = NotInitialized AiInitProgress
    | WaitingForAiAnswer Posix
    | InactiveAi


type AiInitProgress
    = NotStarted
    | ModelLoading Int Int
    | SessionLoading
    | WarmupEvaluation


describeInitProgress : AiInitProgress -> String
describeInitProgress progress =
    case progress of
        NotStarted ->
            "Not started"

        ModelLoading loaded total ->
            "Downloading Model: " ++ String.fromInt loaded ++ "/" ++ String.fromInt total

        SessionLoading ->
            "Setting up Runtime"

        WarmupEvaluation ->
            "Warmup"


{-| Decodes the state we get from javascript into a form that Elm can use. The messages are heterogeneous,
so we need to use oneOf.

{ state: "ModelLoading", loaded: 1312, total: 1887 } -> ModelLoading 1312 1887
"SessionLoading" -> SessionLoading
...

-}
decodeAiState : Json.Decode.Decoder AiState
decodeAiState =
    Json.Decode.oneOf
        [ decodeConstant "SessionLoading" (NotInitialized SessionLoading)
        , decodeModelLoading |> Json.Decode.map NotInitialized
        , decodeConstant "WarmupEvaluation" (NotInitialized WarmupEvaluation)
        , decodeConstant "InactiveAi" InactiveAi
        ]


decodeModelLoading : Json.Decode.Decoder AiInitProgress
decodeModelLoading =
    Json.Decode.map3 (\l t _ -> ModelLoading l t)
        (Json.Decode.field "loaded" Json.Decode.int)
        (Json.Decode.field "total" Json.Decode.int)
        (Json.Decode.field "state" (decodeConstant "ModelLoading" ()))


aiStateSub : (String -> a) -> (AiState -> a) -> Sub a
aiStateSub errorConstructor constructor =
    Api.MessageGen.subscribePort errorConstructor Api.MessageGen.aiStateUpdated decodeAiState constructor
