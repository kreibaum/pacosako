module TileParsingTest exposing (..)

import Expect
import Test exposing (..)
import Tile exposing (Tile(..))


suite : Test
suite =
    describe "Converts every possible board location into a string (e.g. ''c7'') and back again."
        (List.range 0 63 |> List.map testOneTile)


testOneTile : Int -> Test
testOneTile id =
    test ("Test for tile with id = " ++ String.fromInt id) <|
        \() ->
            Expect.equal
                (Tile.fromFlat id |> Just)
                (Tile.fromFlat id |> Tile.toIdentifier |> Tile.fromIdentifier)
