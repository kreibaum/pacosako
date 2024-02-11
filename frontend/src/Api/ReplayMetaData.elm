module Api.ReplayMetaData exposing (ReplayCue(..), ReplayMetaDataProcessed, empty, error, filter, getReplayMetaData)

import Api.Backend exposing (Api, getJson)
import Arrow exposing (Arrow)
import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Sako
import Set exposing (Set)


empty : ReplayMetaDataProcessed
empty =
    Dict.empty


error : ReplayMetaDataProcessed
error =
    Dict.singleton "Error" (Dict.singleton 0 [ CueString "Error downloading replay meta data." ])


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
        Just cues ->
            cues ++ accumulator

        Nothing ->
            accumulator


{-| Transport and serialisation type
-}
type alias ReplayMetaData =
    { actionIndex : Int
    , category : String
    , data : String
    }


{-| Type we actually want to use for the replay
-}
type alias ReplayMetaDataProcessed =
    Dict String (Dict Int (List ReplayCue))


{-| Same as ReplayMetaDataProcessed, but "Raw" i.e. no data transforms
-}
type alias ReplayMetaDataProcessedStage1 =
    Dict String (Dict Int (List ReplayCueRaw))


type ReplayCue
    = CueString String
    | CueArrow Arrow
    | CueValue CueValueData


type alias CueValueData =
    { valueBefore : Float
    , valueAfter : Float
    , impact : Float
    , impactAlt : Float
    , surprise : Float
    , kendall : Float
    }


{-| Process a list of ReplayMetaData into the desired ReplayMetaDataProcessed format.

    This function works by folding over the list of ReplayMetaData and updating the
    ReplayMetaDataProcessed dictionary one item at a time using the processReplayItem function.

-}
processReplayMetaData : List ReplayMetaData -> ReplayMetaDataProcessed
processReplayMetaData replayList =
    List.foldl processReplayItem Dict.empty replayList
        |> mapByGrouping weightDistribution
        |> cookCues


{-| Process an individual ReplayMetaData item and update the ReplayMetaDataProcessed dictionary.

    For a given ReplayMetaData:
    1. Check if its category exists in the dictionary:
        a. If it doesn't, treat the category as having an empty dictionary of indices.
    2. For that category, check if its action index exists:
        a. If it doesn't, create a new list with the ReplayCue.
        b. If it does, append the ReplayCue to the existing list for that action index.
    3. Return the updated ReplayMetaDataProcessed dictionary.

-}
processReplayItem : ReplayMetaData -> ReplayMetaDataProcessedStage1 -> ReplayMetaDataProcessedStage1
processReplayItem replayItem processed =
    let
        newCue =
            parseReplayCue replayItem.data

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
        , decoder =
            Decode.list decodeReplayMetaData
                |> Decode.map processReplayMetaData
        }


decodeReplayMetaData : Decoder ReplayMetaData
decodeReplayMetaData =
    Decode.map3 ReplayMetaData
        (Decode.field "action_index" Decode.int)
        (Decode.field "category" Decode.string)
        (Decode.field "data" Decode.string)


parseReplayCue : String -> ReplayCueRaw
parseReplayCue input =
    Decode.decodeString decodeReplayCue input
        |> Result.withDefault (CueStringRaw input)


decodeReplayCue : Decoder ReplayCueRaw
decodeReplayCue =
    Decode.oneOf
        [ guardType "arrow" decodeArrow
        , guardType "value" decodeValue
        ]


{-| Ensure the "type" field matches the expected value. If it does, proceed with the given decoder.
If it doesn't, fail the decoding.
-}
guardType : String -> Decoder a -> Decoder a
guardType expectedType nextDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\actualType ->
                if actualType == expectedType then
                    nextDecoder

                else
                    Decode.fail ("Expected type '" ++ expectedType ++ "' but got '" ++ actualType ++ "'")
            )


decodeArrow : Decoder ReplayCueRaw
decodeArrow =
    Decode.map5 ArrowRaw
        (Decode.field "head" Sako.decodeFlatTile)
        (Decode.field "tail" Sako.decodeFlatTile)
        (decodeWithDefault Arrow.defaultTailWidth (Decode.field "width" Decode.float))
        (decodeWithDefault Arrow.defaultArrowColor (Decode.field "color" Decode.string))
        (decodeWithDefault 0 (Decode.field "weight" Decode.float))
        |> Decode.map CueArrowRaw


decodeValue : Decoder ReplayCueRaw
decodeValue =
    Decode.map6 CueValueData
        (Decode.field "value_before" Decode.float)
        (Decode.field "value_after" Decode.float)
        (Decode.field "impact" Decode.float)
        (Decode.field "impact_alt" Decode.float)
        (Decode.field "surprise" Decode.float)
        (Decode.field "kendall" Decode.float)
        |> Decode.map CueValueRaw


decodeWithDefault : a -> Decoder a -> Decoder a
decodeWithDefault default decoder =
    Decode.maybe decoder
        |> Decode.map (Maybe.withDefault default)



--------------------------------------------------------------------------------
-- Raw types and transformations -----------------------------------------------
--------------------------------------------------------------------------------


{-| Unprocessed replay cue. There are some preprocessing steps like the
weight -> width transformation that are applied at this stage.
-}
type ReplayCueRaw
    = CueStringRaw String
    | CueArrowRaw ArrowRaw
    | CueValueRaw CueValueData


type alias ArrowRaw =
    { head : Sako.Tile
    , tail : Sako.Tile
    , width : Float
    , color : String
    , weight : Float
    }


mapByGrouping : (a -> b) -> Dict String (Dict Int a) -> Dict String (Dict Int b)
mapByGrouping f dictDict =
    Dict.map (\_ d -> Dict.map (\_ l -> f l) d) dictDict


{-| This is just an elaborate `map cookCue` on a monad stack.
Used to turn a raw cue into a non-raw cue inside the processed replay meta data.
-}
cookCues : ReplayMetaDataProcessedStage1 -> ReplayMetaDataProcessed
cookCues categories =
    mapByGrouping (List.map cookCue) categories


cookCue : ReplayCueRaw -> ReplayCue
cookCue cue =
    case cue of
        CueStringRaw x ->
            CueString x

        CueArrowRaw x ->
            CueArrow (Arrow.Arrow x.head x.tail x.width x.color)

        CueValueRaw x ->
            CueValue x


weightToDistribute : Float
weightToDistribute =
    30


{-| Takes a certain total width and distributes it amongs all arrows that have
a positive "weight" value. This allows you to display a policy without
determining the weights yourself.
-}
weightDistribution : List ReplayCueRaw -> List ReplayCueRaw
weightDistribution arrows =
    let
        total =
            arrows
                |> List.filterMap
                    (\cue ->
                        case cue of
                            CueArrowRaw arrow ->
                                Just arrow.weight

                            _ ->
                                Nothing
                    )
                |> List.filter (\x -> x > 0)
                |> List.sum
    in
    arrows
        |> List.map
            (\cue ->
                case cue of
                    CueArrowRaw arrow ->
                        if arrow.weight > 0 then
                            CueArrowRaw { arrow | width = weightToDistribute * arrow.weight / total }

                        else
                            cue

                    c ->
                        c
            )
