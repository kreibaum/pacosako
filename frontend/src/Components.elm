module Components exposing (gameIdBadgeBig, header1, header2, header3, iconButton, paragraph)

{-| Module to collect small reusable ui components. Everything in this root module
should not have their own message type or their own complicated data.
-}

import Custom.Element exposing (icon)
import Element exposing (Element, centerX, fill, height, padding, spacing, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input exposing (button)
import Element.Region exposing (description)
import FontAwesome.Icon exposing (Icon)


{-| A label that is implemented via a horizontal row with a big colored background.
Currently only used for the timer, not sure if it will stay that way.
-}
gameIdBadgeBig : String -> Element msg
gameIdBadgeBig gameId =
    Element.el [ Background.color (Element.rgb255 220 220 220), width fill, Border.rounded 5 ]
        (Element.el [ height fill, centerX, padding 15, spacing 10, Font.size 40 ]
            (Element.text gameId)
        )


{-| Small button that is just an icon and that usually fires a message.
For usability, there must also be an alt text on the button.
-}
iconButton : String -> Icon -> Maybe msg -> Element msg
iconButton altText iconType msg =
    button []
        { onPress = msg
        , label = icon [ description altText ] iconType
        }


header1 : String -> Element msg
header1 caption =
    Element.el [ padding 40, centerX, Font.size 40 ] (Element.text caption)


header2 : String -> Element msg
header2 caption =
    Element.el [ Font.size 30 ] (Element.text caption)


header3 : String -> Element msg
header3 caption =
    Element.el [ Font.bold ] (Element.text caption)


paragraph : String -> Element msg
paragraph content =
    Element.paragraph [] [ Element.text content ]
