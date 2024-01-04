module Api.Decoders exposing (CurrentMatchState, LegalActions(..), PublicUserData, decodeMatchState, decodePublicUserData, getActionList)

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
    , whitePlayer : Maybe PublicUserData
    , blackPlayer : Maybe PublicUserData
    }


type LegalActions
    = ActionsNotLoaded
    | ActionsLoaded (List Sako.Action)


type alias PublicUserData =
    { name : String
    , avatar : String
    , ai : Maybe AiMetaData
    }


type alias AiMetaData =
    { modelName : String
    , modelStrength : Int
    }


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
    Decode.map8
        (\key actionHistory legalActions controllingPlayer timer gameState whitePlayer blackPlayer ->
            { key = key
            , actionHistory = actionHistory
            , legalActions = ActionsLoaded legalActions
            , controllingPlayer = controllingPlayer
            , timer = timer
            , gameState = gameState
            , whitePlayer = whitePlayer
            , blackPlayer = blackPlayer
            }
        )
        (Decode.field "key" Decode.string)
        (Decode.field "actions" (Decode.list Sako.decodeAction))
        (Decode.field "legal_actions" (Decode.list Sako.decodeAction))
        (Decode.field "controlling_player" Sako.decodeColor)
        (Decode.field "timer" (Decode.maybe Timer.decodeTimer))
        (Decode.field "victory_state" Sako.decodeVictoryState)
        (Decode.field "white_player" (Decode.nullable decodePublicUserData))
        (Decode.field "black_player" (Decode.nullable decodePublicUserData))


decodePublicUserData : Decoder PublicUserData
decodePublicUserData =
    Decode.map3 PublicUserData
        (Decode.field "name" Decode.string)
        (Decode.field "avatar" Decode.string)
        (Decode.field "ai" (Decode.nullable decodeAiMetaData))


decodeAiMetaData : Decoder AiMetaData
decodeAiMetaData =
    Decode.map2 AiMetaData
        (Decode.field "model_name" Decode.string)
        (Decode.field "model_strength" Decode.int)
