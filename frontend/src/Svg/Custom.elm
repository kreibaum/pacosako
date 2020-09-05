module Svg.Custom exposing (Coord(..), Rect, addCoord, makeViewBox, translate)

{-| Represents a point in the Svg coordinate space. The game board is rendered from 0 to 800 in
both directions but additional objects are rendered outside.
-}

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
