module FenTest exposing (..)

{-| Test module for the X-Fen we are using.
-}

import Expect exposing (Expectation)
import Fen
import Sako exposing (Color(..), Piece, Tile(..), Type(..))
import Test exposing (..)


suite : Test
suite =
    describe "Test suite for FEN notation"
        [ test "Reading a board with only a single piece" <|
            \() ->
                Fen.parseFen "2n5/8/8/8/8/8/8/8 b 2 bedh -"
                    |> Expect.equal
                        (Just
                            { currentPlayer = White
                            , liftedPieces = []
                            , pieces =
                                [ { color = Black, identity = "enumerate0", pieceType = Knight, position = Tile 2 7 } ]
                            }
                        )
        , test "Reading a board with only a single pair" <|
            \() ->
                Fen.parseFen "8/8/8/1u6/8/8/8/8 b 2 bedh -"
                    |> Expect.equal
                        (Just
                            { currentPlayer = White
                            , liftedPieces = []
                            , pieces =
                                [ { color = White, identity = "enumerate0", pieceType = King, position = Tile 1 4 }
                                , { color = Black, identity = "enumerate1", pieceType = Knight, position = Tile 1 4 }
                                ]
                            }
                        )
        , test "Writing the initial board position as FEN." <|
            \() ->
                Fen.writeFen Sako.initialPosition
                    |> Expect.equal "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w 0 AHah - -"
        , testPositionRoundTrip "Round trip the initial board position via FEN. 2" Sako.initialPosition
        , testFenRoundTrip "FEN -> Sako -> FEN round trip test 1" "bqnrkb1r/pppppppp/5n2/8/3P4/8/PPP1PPPP/NRBKRBNQ w 0 AHah - -"
        , testFenRoundTrip "FEN -> Sako -> FEN round trip test 2" "bqrknbr1/ppeppp1p/8/6p1/2PPn3/3Q4/PP2PPPP/NBR2KNR w 0 AHah - -"
        , testFenRoundTrip "FEN -> Sako -> FEN round trip test 3" "bqrknb2/ppe2p1p/8/4A1dC/2Pf4/2R1P3/PP3PP1/Ns3K1R w 0 AHah - -"
        ]


{-| Test that a given position survives a round trip throuh FEN notation.
-}
testPositionRoundTrip : String -> Sako.Position -> Test
testPositionRoundTrip description position =
    test description <|
        \() ->
            Fen.writeFen position
                |> Fen.parseFen
                |> Maybe.withDefault Sako.emptyPosition
                |> expectPosition position


{-| Tests that a given notation survives a round trip through the Sako.Position
datastructure.
-}
testFenRoundTrip : String -> String -> Test
testFenRoundTrip description notation =
    test description <|
        \() ->
            Fen.parseFen notation
                |> Maybe.withDefault Sako.emptyPosition
                |> Fen.writeFen
                |> Expect.equal notation


{-| Compares the pieces of two positions.
-}
expectPosition : Sako.Position -> Sako.Position -> Expectation
expectPosition expected actual =
    actual.pieces
        |> List.map stripEnumerate
        |> List.sortBy arbitraryPieceSortKey
        |> Expect.equalLists
            (expected.pieces
                |> List.map stripEnumerate
                |> List.sortBy arbitraryPieceSortKey
            )


stripEnumerate : Piece -> Piece
stripEnumerate piece =
    { piece | identity = "" }


{-| Some arbitrary key that can be used to sort List Piece.
-}
arbitraryPieceSortKey : Piece -> Int
arbitraryPieceSortKey piece =
    Sako.tileFlat piece.position
        + 64
        * (if piece.color == White then
            0

           else
            1
          )
        + 128
        * (case piece.pieceType of
            Pawn ->
                0

            Rook ->
                1

            Knight ->
                2

            Bishop ->
                3

            Queen ->
                4

            King ->
                5
          )
