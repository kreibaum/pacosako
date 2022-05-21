module Api.Decoders exposing (CurrentMatchState, LegalActions(..), decodeMatchState, getActionList)

import Json.Decode as Decode exposing (Decoder)
import Sako
import Timer


type alias CurrentMatchState =
    { key : String
    , actionHistory : List Sako.Action
    , legalActions : LegalActions
    , controllingPlayer : Sako.Color
    , timer : Maybe Timer.Timer
    , gameState : Sako.VictoryState
    }


type LegalActions
    = ActionsNotLoaded
    | ActionsLoaded (List Sako.Action)


getActionList : LegalActions -> List Sako.Action
getActionList actionState =
    case actionState of
        ActionsNotLoaded ->
            []

        ActionsLoaded actions ->
            actions


{-| Some decoders are shared by the REST endpoints and by the websocket
endpoints. This is the file for those.
-}
decodeMatchState : Decoder CurrentMatchState
decodeMatchState =
    Decode.map6
        (\key actionHistory legalActions controllingPlayer timer gameState ->
            { key = key
            , actionHistory = actionHistory
            , legalActions = ActionsLoaded legalActions
            , controllingPlayer = controllingPlayer
            , timer = timer
            , gameState = gameState
            }
        )
        (Decode.field "key" Decode.string)
        (Decode.field "actions" (Decode.list Sako.decodeAction))
        (Decode.field "legal_actions" (Decode.list Sako.decodeAction))
        (Decode.field "controlling_player" Sako.decodeColor)
        (Decode.field "timer" (Decode.maybe Timer.decodeTimer))
        (Decode.field "victory_state" Sako.decodeVictoryState)
