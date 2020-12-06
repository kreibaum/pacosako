module Components exposing (gameIdBadgeBig)

{-| Module to collect small reusable ui components. Everything in this root module
should not have their own message type or their own complicated data.
-}

import Element exposing (Element, centerX, fill, height, padding, spacing, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font


{-| A label that is implemented via a horizontal row with a big colored background.
Currently only used for the timer, not sure if it will stay that way.
-}
gameIdBadgeBig : String -> Element msg
gameIdBadgeBig gameId =
    Element.el [ Background.color (Element.rgb255 220 220 220), width fill, height fill, Border.rounded 5 ]
        (Element.el [ height fill, centerX, padding 15, spacing 10, Font.size 40 ]
            (Element.text gameId)
        )
