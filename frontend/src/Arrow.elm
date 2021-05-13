module Arrow exposing (Arrow, toSvg)

{-| This module renders the arrow that is used to point from one tile to another
tile. An arrow is given as a labeled pair of Tiles {head, tail}.
-}

import Sako exposing (Tile(..))
import Svg exposing (Svg)
import Svg.Attributes as SvgA
import Svg.Custom as Svg exposing (BoardRotation(..))


type alias Arrow =
    { head : Tile
    , tail : Tile
    }


toSvg : BoardRotation -> List (Svg.Attribute a) -> Arrow -> Svg a
toSvg rotation attributes arrow =
    if arrow.head /= arrow.tail then
        Svg.path
            ([ matrixTrafo rotation arrow
             , arrowPath arrow
             ]
                ++ attributes
            )
            []

    else
        Svg.path [] []


{-| Given a logical tile, compute the top left corner coordinates in the svg
coordinate system.
-}
coordinateOfTileFloat : BoardRotation -> Tile -> ( Float, Float )
coordinateOfTileFloat rotation tile =
    let
        (Svg.Coord x y) =
            Svg.coordinateOfTile rotation tile
    in
    ( toFloat x, toFloat y )


tailWidth : Float
tailWidth =
    10


headWidth : Float
headWidth =
    40


delta : BoardRotation -> Arrow -> ( Float, Float )
delta rotation arrow =
    let
        ( x1, y1 ) =
            coordinateOfTileFloat rotation arrow.tail

        ( x2, y2 ) =
            coordinateOfTileFloat rotation arrow.head
    in
    ( x2 - x1, y2 - y1 )


length : Arrow -> Float
length arrow =
    let
        ( dx, dy ) =
            -- The length is independent of the orientation.
            delta WhiteBottom arrow
    in
    sqrt (dx ^ 2 + dy ^ 2)


arrowPath : Arrow -> Svg.Attribute a
arrowPath arrow =
    let
        l =
            length arrow
    in
    SvgA.d
        ("m 0 0 v "
            ++ String.fromFloat (-tailWidth / 2)
            ++ " h "
            ++ String.fromFloat (l - headWidth / 2)
            ++ " v "
            ++ String.fromFloat (-(headWidth - tailWidth) / 2)
            -- Now we move to the tip of the arrow head
            ++ " L "
            ++ String.fromFloat l
            ++ " 0 "
            -- Second half of the arrow head
            ++ " l "
            ++ String.fromFloat -(headWidth / 2)
            ++ " "
            ++ String.fromFloat (headWidth / 2)
            ++ " v "
            ++ String.fromFloat (-(headWidth - tailWidth) / 2)
            -- And back to the tail
            ++ " h "
            ++ String.fromFloat -(l - headWidth / 2)
            ++ " z"
        )


{-| I sat down with a piece of paper and a pencil and worked out those formulas.
This is a transformation which projects (0, 0) to arrow.tail and
projects (L, 0) to arrow.head, while preserving angles and distances.
-}
matrixTrafo : BoardRotation -> Arrow -> Svg.Attribute a
matrixTrafo rotation arrow =
    let
        ( x1, y1 ) =
            coordinateOfTileFloat rotation arrow.tail

        ( dx, dy ) =
            delta rotation arrow

        l =
            length arrow

        a =
            dx / l

        b =
            dy / l

        c =
            -b

        d =
            a

        e =
            x1

        f =
            y1
    in
    SvgA.transform
        ("matrix("
            ++ String.fromFloat a
            ++ " "
            ++ String.fromFloat b
            ++ " "
            ++ String.fromFloat c
            ++ " "
            ++ String.fromFloat d
            ++ " "
            ++ String.fromFloat (e + 50)
            ++ " "
            ++ String.fromFloat (f + 50)
            ++ ")"
        )
