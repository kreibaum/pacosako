module Svg.Custom exposing (BoardRotation(..), Coord(..), Rect, addCoord, coordinateOfTile, flagEn, flagEo, flagNl, makeViewBox, safeTileCoordinate, translate)

{-| Represents a point in the Svg coordinate space. The game board is rendered from 0 to 800 in
both directions but additional objects are rendered outside.

TODO: Should go into Custom.Svg

-}

import Html exposing (Html)
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


{-| Svg of the flag of the United Kingdom.
-}
flagEn : Html a
flagEn =
    Svg.svg [ SvgA.viewBox "0 0 60 30", SvgA.width "40px", SvgA.height "20px" ]
        [ Svg.clipPath [ SvgA.id "s" ] [ Svg.path [ SvgA.d "M0,0 v30 h60 v-30 z" ] [] ]
        , Svg.clipPath [ SvgA.id "t" ] [ Svg.path [ SvgA.d "M30,15 h30 v15 z v15 h-30 z h-30 v-15 z v-15 h30 z" ] [] ]
        , Svg.g [ SvgA.clipPath "url(#s)" ]
            [ Svg.path [ SvgA.d "M0,0 v30 h60 v-30 z", SvgA.fill "#012169" ] []
            , Svg.path [ SvgA.d "M0,0 L60,30 M60,0 L0,30", SvgA.stroke "#fff", SvgA.strokeWidth "6" ] []
            , Svg.path [ SvgA.d "M0,0 L60,30 M60,0 L0,30", SvgA.clipPath "url(#t)", SvgA.stroke "#C8102E", SvgA.strokeWidth "4" ] []
            , Svg.path [ SvgA.d "M30,0 v30 M0,15 h60", SvgA.stroke "#fff", SvgA.strokeWidth "10" ] []
            , Svg.path [ SvgA.d "M30,0 v30 M0,15 h60", SvgA.stroke "#C8102E", SvgA.strokeWidth "6" ] []
            ]
        ]


{-| Svg of the flag of the Netherlands.
-}
flagNl : Html a
flagNl =
    Svg.svg [ SvgA.viewBox "0 0 9 6", SvgA.width "30px", SvgA.height "20px" ]
        [ Svg.rect [ SvgA.fill "#21468B", SvgA.width "9", SvgA.height "6" ] []
        , Svg.rect [ SvgA.fill "#FFF", SvgA.width "9", SvgA.height "4" ] []
        , Svg.rect [ SvgA.fill "#AE1C28", SvgA.width "9", SvgA.height "2" ] []
        ]


{-| Svg of the Esperanto Flag.
-}
flagEo : Html a
flagEo =
    Svg.svg [ SvgA.viewBox "0 0 600 400", SvgA.width "30px", SvgA.height "20px" ]
        [ Svg.path [ SvgA.fill "#FFF", SvgA.d "m0,0h202v202H0" ] []
        , Svg.path [ SvgA.fill "#090", SvgA.d "m0,200H200V0H600V400H0m58-243 41-126 41,126-107-78h133" ] []
        ]
