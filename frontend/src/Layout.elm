module Layout exposing (vScollBox)

import Element exposing (Element, column, fill, height, scrollbarY, width)


{-| This wrapper makes sure the inner content scrolls vertically without
affecting the exterior. This makes sure the header stays in place.
-}
vScollBox : List (Element msg) -> Element msg
vScollBox content =
    column
        [ width fill
        , height fill
        , scrollbarY
        ]
        content
