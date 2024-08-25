module Ai exposing (AiInitProgress(..), AiState(..), aiProgressLabel, aiSlowdownLabel, aiStateSub, describeInitProgress, initAiState, isInitialized, startUpAi)

{-| We include Machine Learning based AI through ONNX files and use the javascript-side onnx-runtime to execute them.
We also have an opening book. This means a lot of things need to load (ideally from cache) before the AI is ready to play.
We need to add this as an explicit step before starting a game, so you don't start games without the AI being ready.
It also helps users understand if the AI is broken on their device. Otherwise the start is played by the opening book
and once the model takes over the game just stops.
-}

import Api.MessageGen
import Components exposing (colorButton)
import Custom.Decode exposing (decodeConstant)
import Element exposing (Element, fill, width)
import FontAwesome.Attributes
import FontAwesome.Icon
import FontAwesome.Solid as Solid
import Json.Decode
import Json.Encode
import Time exposing (Posix)
import Translations as T


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
    | AiReadyForRequest


{-| Detailed information about where the AI initialisation is currently at. This can help the user understand why they
are waiting and if there is a problem they can better tell me about it.
-}
type AiInitProgress
    = NotStarted
    | StartRequested
    | ModelLoading Int Int
    | SessionLoading
    | WarmupEvaluation


isInitialized : AiState -> Bool
isInitialized state =
    case state of
        NotInitialized _ ->
            False

        _ ->
            True


describeInitProgress : AiInitProgress -> String
describeInitProgress progress =
    case progress of
        NotStarted ->
            T.aiLabelAiNotStarted

        StartRequested ->
            T.aiLabelAiStartRequested

        ModelLoading loaded total ->
            T.aiLabelModelLoading
                |> String.replace "{0}" (String.fromInt loaded)
                |> String.replace "{1}" (String.fromInt total)

        SessionLoading ->
            T.aiLabelSessionLoading

        WarmupEvaluation ->
            T.aiLabelWarmup


{-| Shown in the AI setup box while the AI is setting up.
-}
aiProgressLabel : AiInitProgress -> Element msg
aiProgressLabel progress =
    colorButton [ width fill ]
        { background = Element.rgb255 180 180 180
        , backgroundHover = Element.rgb255 180 180 180
        , onPress = Nothing
        , buttonIcon =
            Element.html
                (FontAwesome.Icon.viewStyled [ FontAwesome.Attributes.spin ]
                    Solid.spinner
                )
        , caption = describeInitProgress progress
        }


{-| A label you can show to indicate that the AI is taking more time than expected.
-}
aiSlowdownLabel : Posix -> Posix -> Element msg
aiSlowdownLabel now startTime =
    colorButton [ width fill ]
        { background = Element.rgb255 180 180 180
        , backgroundHover = Element.rgb255 180 180 180
        , onPress = Nothing
        , buttonIcon =
            Element.html
                (FontAwesome.Icon.viewStyled [ FontAwesome.Attributes.spin ]
                    Solid.spinner
                )
        , caption =
            T.aiLabelAiStuck
                |> String.replace "{0}"
                    (String.fromInt ((Time.posixToMillis now - Time.posixToMillis startTime) // 1000))
        }


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
        , decodeConstant "AiReadyForRequest" AiReadyForRequest
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
