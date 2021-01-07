module FenTest exposing (..)

{-| Test module for the X-Fen we are using.
-}

import Expect exposing (Expectation)
import Fen
import Fuzz exposing (Fuzzer, int, list, string)
import Http exposing (Expect)
import Sako
import Test exposing (..)


suite : Test
suite =
    describe "Converting a single charater into pieces"
        [ test "'p' is a Pawn" <|
            \() -> Fen.piecesOnTile 'p' |> Expect.equal (Fen.SinglePieceOnTile Sako.Pawn)
        , test "'k' is a King" <|
            \() -> Fen.piecesOnTile 'k' |> Expect.equal (Fen.SinglePieceOnTile Sako.King)
        ]
