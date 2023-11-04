module Notation exposing
    ( HalfMove
    , HalfMoveMetadata
    , HalfMoveSection
    , SectionIndex
    , actionIndexForSectionIndex
    , decodeHalfMove
    , initialSectionIndex
    , lastAction
    , lastSectionIndex
    , lastSectionIndexOfHalfMove
    , nextAction
    , nextMove
    , previousAction
    , previousMove
    , sectionIndexDiff
    , sectionIndexDiffIsForward
    )

{-| Implements Paco Ŝako Style Notation.

All the implementation details are in rust, this is just a wrapper around it.

-}

import Json.Decode as Decode exposing (Decoder)
import List.Extra as List
import Sako



--------------------------------------------------------------------------------
-- New Notation we get from wasm -----------------------------------------------
--------------------------------------------------------------------------------


type alias HalfMove =
    { moveNumber : Int
    , current_player : Sako.Color
    , actions : List HalfMoveSection
    , metadata : HalfMoveMetadata
    }


type alias HalfMoveSection =
    { actionIndex : Int
    , label : String
    }


type alias HalfMoveMetadata =
    { givesSako : Bool
    , missedPaco : Bool
    , givesOpponentPacoOpportunity : Bool
    , pacoIn2Found : Bool
    , pacoIn2Missed : Bool
    }


decodeHalfMove : Decoder HalfMove
decodeHalfMove =
    Decode.map4 HalfMove
        (Decode.field "move_number" Decode.int)
        (Decode.field "current_player" Sako.decodeColor)
        (Decode.field "actions" (Decode.list decodeHalfMoveSection))
        (Decode.field "metadata" decodeHalfMoveMetadata)


decodeHalfMoveSection : Decoder HalfMoveSection
decodeHalfMoveSection =
    Decode.map2 HalfMoveSection
        (Decode.field "action_index" Decode.int)
        (Decode.field "label" Decode.string)


decodeHalfMoveMetadata : Decoder HalfMoveMetadata
decodeHalfMoveMetadata =
    Decode.map5
        HalfMoveMetadata
        (Decode.field "gives_sako" Decode.bool)
        (Decode.field "missed_paco" Decode.bool)
        (Decode.field "gives_opponent_paco_opportunity" Decode.bool)
        (Decode.field "paco_in_2_found" Decode.bool)
        (Decode.field "paco_in_2_missed" Decode.bool)


{-| Since a section is what you highlight in the replay view, we also want to
store this information in a structured way.
-}
type alias SectionIndex =
    { halfMoveIndex : Int
    , sectionIndex : Int
    }


{-| Calculate the pointwise difference between two SectionIndex values.
-}
sectionIndexDiff : SectionIndex -> SectionIndex -> SectionIndex
sectionIndexDiff a b =
    { halfMoveIndex = a.halfMoveIndex - b.halfMoveIndex
    , sectionIndex = a.sectionIndex - b.sectionIndex
    }


{-| To be used in conjunction with sectionIndexDiff. Indicates if the resulting
difference is pointing forward in time.
-}
sectionIndexDiffIsForward : SectionIndex -> Bool
sectionIndexDiffIsForward diff =
    diff.halfMoveIndex > 0 || (diff.halfMoveIndex == 0 && diff.sectionIndex > 0)


{-| References the position before the move history, this is the initial board state.
-}
initialSectionIndex : SectionIndex
initialSectionIndex =
    { halfMoveIndex = -1
    , sectionIndex = 0
    }


lastSectionIndexOfHalfMove : Int -> HalfMove -> SectionIndex
lastSectionIndexOfHalfMove halfMoveIndex halfMove =
    { halfMoveIndex = halfMoveIndex
    , sectionIndex = List.length halfMove.actions - 1
    }


actionIndexForSectionIndex : List HalfMove -> SectionIndex -> Int
actionIndexForSectionIndex halfMoves { halfMoveIndex, sectionIndex } =
    if halfMoveIndex < 0 then
        0

    else
        halfMoves
            |> List.drop halfMoveIndex
            |> List.head
            |> Maybe.map .actions
            |> Maybe.map (List.drop sectionIndex)
            |> Maybe.andThen List.head
            |> Maybe.map .actionIndex
            |> Maybe.withDefault 0


{-| This goes forward one action.
-}
nextAction : List HalfMove -> SectionIndex -> SectionIndex
nextAction ctx index =
    let
        currentHalfMoveLength =
            ctx
                |> List.drop index.halfMoveIndex
                |> List.head
                |> Maybe.map .actions
                |> Maybe.map List.length
                |> Maybe.withDefault 0
    in
    if index.sectionIndex + 1 < currentHalfMoveLength then
        { index | sectionIndex = index.sectionIndex + 1 }

    else if index.halfMoveIndex + 1 < List.length ctx then
        { halfMoveIndex = index.halfMoveIndex + 1, sectionIndex = 0 }

    else
        index


{-| This goes back one action.
-}
previousAction : List HalfMove -> SectionIndex -> SectionIndex
previousAction ctx index =
    if index.sectionIndex > 0 then
        { index | sectionIndex = index.sectionIndex - 1 }

    else
        previousMove ctx index


lastAction : List HalfMove -> Int
lastAction ctx =
    List.last ctx
        |> Maybe.andThen (\hm -> List.last hm.actions)
        |> Maybe.map .actionIndex
        |> Maybe.withDefault 0


lastSectionIndex : List HalfMove -> SectionIndex
lastSectionIndex ctx =
    { halfMoveIndex = List.length ctx - 1
    , sectionIndex =
        List.last ctx
            |> Maybe.map lastSectionOf
            |> Maybe.withDefault 0
    }


{-| This jumps to the end of the next HalfMove.
-}
nextMove : List HalfMove -> SectionIndex -> SectionIndex
nextMove ctx index =
    let
        newHalfMoveIndex =
            min (List.length ctx - 1) (index.halfMoveIndex + 1)

        newSectionIndex =
            ctx
                |> List.drop newHalfMoveIndex
                |> List.head
                |> Maybe.map lastSectionOf
                |> Maybe.withDefault 0
    in
    { halfMoveIndex = newHalfMoveIndex, sectionIndex = newSectionIndex }


{-| This jumps to the end of the previous HalfMove.
-}
previousMove : List HalfMove -> SectionIndex -> SectionIndex
previousMove ctx index =
    let
        newHalfMoveIndex =
            max -1 (index.halfMoveIndex - 1)
    in
    { halfMoveIndex = newHalfMoveIndex
    , sectionIndex =
        ctx |> List.drop newHalfMoveIndex |> List.head |> Maybe.map lastSectionOf |> Maybe.withDefault 0
    }


lastSectionOf : HalfMove -> Int
lastSectionOf halfMove =
    halfMove.actions
        |> List.length
        |> (\i -> i - 1)
