port module Api.MessageGen exposing (..)

{-| This module is a (fake) generated module that has ports for all the messages
that elm may receive. Eventually I want to replace this by an actually generated
module when iI know my requirements better.
-}

import Json.Decode exposing (Decoder, Value, errorToString)



--------------------------------------------------------------------------------
-- Utility functions to be used with this module -------------------------------
--------------------------------------------------------------------------------


subscribePort : (String -> msg) -> ((Value -> msg) -> Sub msg) -> Decoder a -> (a -> msg) -> Sub msg
subscribePort errorConstructor portFunction decoder constructor =
    portFunction
        (\value ->
            case Json.Decode.decodeValue decoder value of
                Ok result ->
                    constructor result

                Err error ->
                    errorConstructor (errorToString error)
        )



--------------------------------------------------------------------------------
-- Messages send from the elm app to the outside world -------------------------
--------------------------------------------------------------------------------


{-| Gets all legal actions for a position
-}
port determineLegalActions : Value -> Cmd msg


{-| Sends a message that a random position should be generated
-}
port generateRandomPosition : Value -> Cmd msg


{-| Asks for a position to be analyzed
-}
port analyzePosition : Value -> Cmd msg


{-| Asks for a replay to be analyzed
-}
port analyzeReplay : Value -> Cmd msg


{-| Signs up for the status of the given match.
-}
port subscribeToMatch : Value -> Cmd msg


{-| Signs up for the status of the given match.
-}
port determineAiMove : Value -> Cmd msg



--------------------------------------------------------------------------------
-- Messages send from the outside world to the elm app -------------------------
--------------------------------------------------------------------------------


{-| Response for determineLegalActions with moves determined
-}
port legalActionsDetermined : (Value -> msg) -> Sub msg


{-| A random position has been generated.
-}
port randomPositionGenerated : (Value -> msg) -> Sub msg


{-| Position analysis has been completed.
-}
port positionAnalysisCompleted : (Value -> msg) -> Sub msg


{-| Replay analysis has been completed.
-}
port replayAnalysisCompleted : (Value -> msg) -> Sub msg


{-| Is called one or more times after the AI is asked to determine a move.
-}
port aiMoveDetermined : (Value -> msg) -> Sub msg
