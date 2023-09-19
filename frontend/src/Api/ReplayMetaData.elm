module Api.ReplayMetaData exposing (empty, error, filter, ReplayMetaDataProcessed, ReplayCue(..), getReplayMetaData)

import Json.Decode as Decode exposing (Decoder)
import Dict exposing (Dict)
import Set exposing (Set)
import Api.Backend exposing (Api, getJson)
import Sako

empty : ReplayMetaDataProcessed
empty = Dict.empty

error : ReplayMetaDataProcessed
error = Dict.singleton "Error" ( Dict.singleton 0 [ CueString "Error downloading replay meta data."] )

{-| Filters and retrieves a list of `ReplayCue` based on a set of allowed categories and an action index.

    Given a set of categories and an action index, this function extracts all the `ReplayCue`
    items from the `ReplayMetaDataProcessed` dictionary that match the criteria.

    - If a category is not present in the set, it's ignored.
    - If an action index doesn't exist for a category, it's ignored.

-}
filter : Set String -> Int -> ReplayMetaDataProcessed -> List ReplayCue
filter allowedCategories actionIndex replayMetaData =
    replayMetaData
        |> Dict.filter (\category _ -> Set.member category allowedCategories)
        |> Dict.foldl (accumulateCuesForAction actionIndex) []

accumulateCuesForAction : Int -> String -> Dict Int (List ReplayCue) -> List ReplayCue -> List ReplayCue
accumulateCuesForAction actionIndex _ categoryDict accumulator =
    case Dict.get actionIndex categoryDict of
        Just cues -> cues ++ accumulator
        Nothing -> accumulator

{-| Transport and serialisation type -}
type alias ReplayMetaData =
    { actionIndex : Int
    , category : String
    , data : String
    }

{-| Type we actually want to use for the replay -}
type alias ReplayMetaDataProcessed = Dict String (Dict Int (List ReplayCue))

type ReplayCue
    = CueString String
    | CueArrow CueArrowData

type alias CueArrowData = { start : Sako.Tile, end : Sako.Tile }


{-| Process a list of ReplayMetaData into the desired ReplayMetaDataProcessed format.
    
    This function works by folding over the list of ReplayMetaData and updating the 
    ReplayMetaDataProcessed dictionary one item at a time using the processReplayItem function.
-}
processReplayMetaData : List ReplayMetaData -> ReplayMetaDataProcessed
processReplayMetaData replayList =
    List.foldl processReplayItem Dict.empty replayList


{-| Process an individual ReplayMetaData item and update the ReplayMetaDataProcessed dictionary.

    For a given ReplayMetaData:
    1. Check if its category exists in the dictionary:
        a. If it doesn't, treat the category as having an empty dictionary of indices.
    2. For that category, check if its action index exists:
        a. If it doesn't, create a new list with the ReplayCue.
        b. If it does, append the ReplayCue to the existing list for that action index.
    3. Return the updated ReplayMetaDataProcessed dictionary.
-}
processReplayItem : ReplayMetaData -> ReplayMetaDataProcessed -> ReplayMetaDataProcessed
processReplayItem replayItem processed =
    let
        newCue = parseReplayCue replayItem.data

        categoryDict =
            Dict.get replayItem.category processed
                |> Maybe.withDefault Dict.empty

        updatedActionList =
            Dict.get replayItem.actionIndex categoryDict
                |> Maybe.map (\currentList -> newCue :: currentList)
                |> Maybe.withDefault [ newCue ]

        updatedCategoryDict =
            Dict.insert replayItem.actionIndex updatedActionList categoryDict
    in
    Dict.insert replayItem.category updatedCategoryDict processed


getReplayMetaData : String -> Api ReplayMetaDataProcessed msg
getReplayMetaData key =
    getJson
        { url = "/api/replay_meta_data/" ++ key
        , decoder = (Decode.list decodeReplayMetaData)
            |> Decode.map processReplayMetaData
        }

decodeReplayMetaData : Decoder ReplayMetaData
decodeReplayMetaData =
    Decode.map3 ReplayMetaData
        (Decode.field "action_index" Decode.int)
        (Decode.field "category" Decode.string)
        (Decode.field "data" Decode.string)


parseReplayCue : String -> ReplayCue
parseReplayCue input =
    Decode.decodeString decodeReplayCue input
        |> Result.withDefault (CueString input)

decodeReplayCue : Decoder ReplayCue
decodeReplayCue =
    Decode.oneOf [
        guardType "arrow" decodeArrow
    ]

{-| Ensure the "type" field matches the expected value. If it does, proceed with the given decoder.
    If it doesn't, fail the decoding.
-}
guardType : String -> Decoder a -> Decoder a
guardType expectedType nextDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen (\actualType ->
            if actualType == expectedType then
                nextDecoder
            else
                Decode.fail ("Expected type '" ++ expectedType ++ "' but got '" ++ actualType ++ "'")
           )

decodeArrow : Decoder ReplayCue
decodeArrow =
    Decode.map2 CueArrowData
        (Decode.field "start" Sako.decodeFlatTile)
        (Decode.field "end" Sako.decodeFlatTile)
        |> Decode.map CueArrow