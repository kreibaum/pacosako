module Layout exposing
    ( textPageWrapper
    , vScollBox
    )

import Element exposing (Element, column, fill, height, scrollbarY, width, maximum, centerX, padding, spacing)

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


textPageWrapper : List (Element msg) -> Element msg
textPageWrapper content =
    vScollBox
        [ Element.column [ width (fill |> maximum 1000), centerX, padding 10, spacing 10 ]
            content
        ]
