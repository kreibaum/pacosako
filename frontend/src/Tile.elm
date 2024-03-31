module Tile exposing (..)

import List.Extra as List


{-| Represents the position of a single abstract board tile.
`Tile x y` stores two integers with legal values between 0 and 7 (inclusive).
Use `tileX` and `tileY` to extract individual coordinates.
-}
type Tile
    = Tile Int Int


{-| 1d coordinate for a tile. This is just x + 8 \* y
-}
toFlat : Tile -> Int
toFlat (Tile x y) =
    x + 8 * y


fromFlat : Int -> Tile
fromFlat i =
    Tile (modBy 8 i) (i // 8)


getY : Tile -> Int
getY (Tile _ y) =
    y


getX : Tile -> Int
getX (Tile x _) =
    x


{-| Gets the name of a tile, like "g4" or "c7".
-}
toIdentifier : Tile -> String
toIdentifier (Tile x y) =
    [ List.getAt x (String.toList "abcdefgh") |> Maybe.withDefault '?'
    , List.getAt y (String.toList "12345678") |> Maybe.withDefault '?'
    ]
        |> String.fromList
