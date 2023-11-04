module Api.DecoderGen exposing (..)

{-| Similar to MessageGen, this has some "automated" decoders that are very much
still written by hand for now.
-}

import Json.Decode as Decode exposing (Decoder)
import Notation


randomPositionGenerated : Decoder String
randomPositionGenerated =
    Decode.field "board_fen" Decode.string


positionAnalysisCompleted : Decoder { text_summary : String }
positionAnalysisCompleted =
    Decode.field "text_summary" Decode.string
        |> Decode.map (\a -> { text_summary = a })


type alias ReplayData =
    { notation : List Notation.HalfMove, opening : String, progress : Float }


replayAnalysisCompleted : Decoder ReplayData
replayAnalysisCompleted =
    Decode.map3 ReplayData
        (Decode.field "notation" (Decode.list Notation.decodeHalfMove))
        (Decode.field "opening" Decode.string)
        (Decode.field "progress" Decode.float)
