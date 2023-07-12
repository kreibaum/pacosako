module Api.DecoderGen exposing (..)

{-| Similar to MessageGen, this has some "automated" decoders that are very much
still written by hand for now.
-}

import Json.Decode as Decode exposing (Decoder)


randomPositionGenerated : Decoder String
randomPositionGenerated =
    Decode.field "board_fen" Decode.string
