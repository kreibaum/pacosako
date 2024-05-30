module Api.Decoders exposing (CompressedMatchState, ControlLevel(..), CurrentMatchState, LegalActions(..), PublicUserData, decodeCompressedMatchState, decodeMatchState, decodePublicUserData, getActionList)

import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline exposing (required)
import Sako
import Timer


type alias CurrentMatchState =
    { key : String
    , actionHistory : List Sako.Action
    , isRollback : Bool
    , legalActions : LegalActions
    , controllingPlayer : Sako.Color
    , timer : Maybe Timer.Timer
    , gameState : Sako.VictoryState
    , whitePlayer : Maybe PublicUserData
    , blackPlayer : Maybe PublicUserData
    , whiteControl : ControlLevel
    , blackControl : ControlLevel
    }


type ControlLevel
    = Unlocked
    | LockedByYou
    | LockedByYourFrontendAi
    | LockedByOther


decodeControlLevel : Decoder ControlLevel
decodeControlLevel =
    Decode.string
        |> Decode.andThen
            (\str ->
                case str of
                    "Unlocked" ->
                        Decode.succeed Unlocked

                    "LockedByYou" ->
                        Decode.succeed LockedByYou

                    "LockedByYourFrontendAi" ->
                        Decode.succeed LockedByYourFrontendAi

                    "LockedByOther" ->
                        Decode.succeed LockedByOther

                    _ ->
                        Decode.fail "Invalid control level"
            )


type alias CompressedMatchState =
    { key : String
    , fen : String
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
    , isFrontendAi : Bool
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
    Decode.succeed
        (\key actionHistory isRollback controllingPlayer timer gameState whitePlayer blackPlayer whiteControl blackControl ->
            { key = key
            , actionHistory = actionHistory
            , isRollback = isRollback
            , legalActions = ActionsNotLoaded
            , controllingPlayer = controllingPlayer
            , timer = timer
            , gameState = gameState
            , whitePlayer = whitePlayer
            , blackPlayer = blackPlayer
            , whiteControl = whiteControl
            , blackControl = blackControl
            }
        )
        |> required "key" Decode.string
        |> required "actions" (Decode.list Sako.decodeAction)
        |> required "is_rollback" Decode.bool
        |> required "controlling_player" Sako.decodeColor
        |> required "timer" (Decode.maybe Timer.decodeTimer)
        |> required "victory_state" Sako.decodeVictoryState
        |> required "white_player" (Decode.nullable decodePublicUserData)
        |> required "black_player" (Decode.nullable decodePublicUserData)
        |> required "white_control" decodeControlLevel
        |> required "black_control" decodeControlLevel


decodeCompressedMatchState : Decoder CompressedMatchState
decodeCompressedMatchState =
    Decode.map6 (\key fen victoryState timer whitePlayer blackPlayer -> CompressedMatchState key fen victoryState timer whitePlayer blackPlayer)
        (Decode.field "key" Decode.string)
        (Decode.field "current_fen" Decode.string)
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
    Decode.map3 AiMetaData
        (Decode.field "model_name" Decode.string)
        (Decode.field "model_strength" Decode.int)
        (Decode.field "is_frontend_ai" Decode.bool)
