module Api.EncoderGen exposing (..)

{-| Similar to MessageGen, this has some "automated" encoders that are very much
still written by hand for now.
-}

import Json.Encode as Encode exposing (Value)
import Sako

determineLegalActions :
    { action_history : List Sako.Action
    , setup : Sako.SetupOptions
    }
    -> Value
determineLegalActions { action_history, setup } =
    Encode.object
        [ ( "action_history", Encode.list Sako.encodeAction action_history )
        , ( "setup", Sako.encodeSetupOptions setup )
        ]


analyzePosition :
    { action_history : List Sako.Action
    , setup : Sako.SetupOptions
    }
    -> Value
analyzePosition { action_history, setup } =
    Encode.object
        [ ( "action_history", Encode.list Sako.encodeAction action_history )
        , ( "setup", Sako.encodeSetupOptions setup )
        ]


analyzeReplay :
    { action_history : List Sako.Action
    , setup : Sako.SetupOptions
    }
    -> Value
analyzeReplay { action_history, setup } =
    Encode.object
        [ ( "action_history", Encode.list Sako.encodeAction action_history )
        , ( "setup", Sako.encodeSetupOptions setup )
        ]
