module Custom.Events exposing (BoardMousePosition, onEnter, svgDown, svgMove, svgUp)

{-| The default events we get for SVG graphics are a problem, because they are
using external coordinates. It is a lot easier to work with internal coordinates
of the svg, so we have introduces custom events.

This also implements an onEnter event attribute.

-}

import Element
import Html.Events
import Json.Decode as Decode exposing (Decoder)
import Sako exposing (Tile(..))
import Svg exposing (Attribute)
import Svg.Custom as Svg exposing (BoardRotation, safeTileCoordinate)
import Svg.Events


type alias BoardMousePosition =
    { x : Int
    , y : Int
    , tile : Maybe Tile
    }


boardMousePosition : BoardRotation -> Float -> Float -> BoardMousePosition
boardMousePosition rotation x y =
    { x = round x
    , y = round y
    , tile = safeTileCoordinate rotation (Svg.Coord (round x) (round y))
    }


decodeBoardMousePosition : BoardRotation -> Decoder BoardMousePosition
decodeBoardMousePosition rotation =
    Decode.map2 (boardMousePosition rotation)
        (Decode.at [ "detail", "x" ] Decode.float)
        (Decode.at [ "detail", "y" ] Decode.float)


svgDown : BoardRotation -> (BoardMousePosition -> msg) -> Attribute msg
svgDown rotation message =
    Svg.Events.on "svgdown" (Decode.map message (decodeBoardMousePosition rotation))


svgMove : BoardRotation -> (BoardMousePosition -> msg) -> Attribute msg
svgMove rotation message =
    Svg.Events.on "svgmove" (Decode.map message (decodeBoardMousePosition rotation))


svgUp : BoardRotation -> (BoardMousePosition -> msg) -> Attribute msg
svgUp rotation message =
    Svg.Events.on "svgup" (Decode.map message (decodeBoardMousePosition rotation))


{-| Event attribute that triggens when the element has focus and the user
presses the enter key. This is great for inputs that are not part of a larger
form and where just entering a single value has meaning.
-}
onEnter : msg -> Element.Attribute msg
onEnter msg =
    Element.htmlAttribute
        (Html.Events.on "keyup"
            (Decode.field "key" Decode.string
                |> Decode.andThen
                    (\key ->
                        if key == "Enter" then
                            Decode.succeed msg

                        else
                            Decode.fail "Not the enter key"
                    )
            )
        )
