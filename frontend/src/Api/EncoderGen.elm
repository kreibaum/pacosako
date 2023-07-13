module Api.EncoderGen exposing (..)

{-| Similar to MessageGen, this has some "automated" encoders that are very much
still written by hand for now.
-}

import Json.Encode as Encode exposing (Value)
import Sako


analyzePosition : { board_fen : String, action_history : List Sako.Action } -> Value
analyzePosition { board_fen, action_history } =
    Encode.object
        [ ( "board_fen", Encode.string board_fen )
        , ( "action_history", Encode.list Sako.encodeAction action_history )
        ]
