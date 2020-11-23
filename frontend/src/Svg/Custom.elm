module Svg.Custom exposing (BoardRotation(..), Coord(..), Rect, addCoord, coordinateOfTile, makeViewBox, safeTileCoordinate, translate)

{-| Represents a point in the Svg coordinate space. The game board is rendered from 0 to 800 in
both directions but additional objects are rendered outside.

TODO: Should go into Custom.Svg

-}

import Sako exposing (Color(..), Tile(..))
import Svg
import Svg.Attributes as SvgA


{-| Represents a point in the Svg coordinate space. The game board is rendered from 0 to 800 in
both directions but additional objects are rendered outside.
-}
type Coord
    = Coord Int Int


{-| Add two SVG coordinates, this is applied to each coordinate individually.
-}
addCoord : Coord -> Coord -> Coord
addCoord (Coord x1 y1) (Coord x2 y2) =
    Coord (x1 + x2) (y1 + y2)


{-| A "style='transform: translate(x, y)'" attribute for an svg node.
-}
translate : Coord -> Svg.Attribute msg
translate (Coord x y) =
    SvgA.style
        ("transform: translate("
            ++ String.fromInt x
            ++ "px, "
            ++ String.fromInt y
            ++ "px)"
        )


type alias Rect =
    { x : Float
    , y : Float
    , width : Float
    , height : Float
    }


makeViewBox : Rect -> Svg.Attribute msg
makeViewBox rect =
    String.join
        " "
        [ String.fromFloat rect.x
        , String.fromFloat rect.y
        , String.fromFloat rect.width
        , String.fromFloat rect.height
        ]
        |> SvgA.viewBox


type BoardRotation
    = WhiteBottom
    | BlackBottom


{-| Given a logical tile, compute the top left corner coordinates in the svg
coordinate system.
-}
coordinateOfTile : BoardRotation -> Tile -> Coord
coordinateOfTile rotation (Tile x y) =
    case rotation of
        WhiteBottom ->
            Coord (100 * x) (700 - 100 * y)

        BlackBottom ->
            Coord (700 - 100 * x) (100 * y)


{-| Transforms an Svg coordinate into a logical tile coordinte.
Returns Nothing, if the SvgCoordinate is outside the board.

It holds, that (coordinateOfTile >> safeTileCoordinate) == Just : Tile -> Maybe Tile.

-}
safeTileCoordinate : BoardRotation -> Coord -> Maybe Tile
safeTileCoordinate rotation (Coord x y) =
    if 0 <= x && x < 800 && 0 <= y && y < 800 then
        case rotation of
            WhiteBottom ->
                Just (Tile (x // 100) (7 - y // 100))

            BlackBottom ->
                Just (Tile (7 - x // 100) (y // 100))

    else
        Nothing
