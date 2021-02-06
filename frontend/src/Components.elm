module Components exposing (StyleableButton, btn, gameIdBadgeBig, header1, header2, header3, iconButton, isEnabledIf, isSelectedIf, paragraph, viewButton, withMsg, withMsgIf, withSmallIcon, withStyle)

{-| Module to collect small reusable ui components. Everything in this root module
should not have their own message type or their own complicated data.
-}

import Custom.Element exposing (icon)
import Element exposing (Element, centerX, el, fill, height, padding, row, spacing, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font exposing (center)
import Element.Input exposing (button)
import Element.Region exposing (description)
import FontAwesome.Attributes
import FontAwesome.Icon exposing (Icon)
import Html exposing (select)
import Svg


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


type alias ButtonColor =
    { normal : Element.Color
    , hover : Element.Color
    , selected : Element.Color
    , disabledText : Element.Color
    }


grayButton : ButtonColor
grayButton =
    { normal = Element.rgb255 240 240 240
    , hover = Element.rgb255 220 220 220
    , selected = Element.rgb255 200 200 200
    , disabledText = Element.rgb255 128 128 128
    }


type StyleableButton msg
    = SB
        { caption : String
        , icon : Maybe Icon
        , msg : Maybe msg
        , size : Maybe (Svg.Attribute msg)
        , color : ButtonColor
        , style : List (Element.Attribute msg)
        , selected : Bool
        , enabled : Bool
        }


btn : String -> StyleableButton msg
btn caption =
    SB
        { caption = caption
        , icon = Nothing
        , msg = Nothing
        , size = Nothing
        , color = grayButton
        , style = []
        , selected = False
        , enabled = True
        }


withSmallIcon : Icon -> StyleableButton msg -> StyleableButton msg
withSmallIcon icon (SB data) =
    SB { data | icon = Just icon, size = Just FontAwesome.Attributes.xs }


withMsg : msg -> StyleableButton msg -> StyleableButton msg
withMsg msg (SB data) =
    SB { data | msg = Just msg }


{-| If the condition is True, then the message is taken. Otherwise the button
is not changed.
-}
withMsgIf : Bool -> msg -> StyleableButton msg -> StyleableButton msg
withMsgIf condition msg (SB data) =
    if condition then
        SB { data | msg = Just msg }

    else
        SB data


withStyle : Element.Attribute msg -> StyleableButton msg -> StyleableButton msg
withStyle style (SB data) =
    SB { data | style = style :: data.style }


isSelectedIf : Bool -> StyleableButton msg -> StyleableButton msg
isSelectedIf isSelected (SB data) =
    SB { data | selected = isSelected }


isEnabledIf : Bool -> StyleableButton msg -> StyleableButton msg
isEnabledIf isEnabled (SB data) =
    SB { data | enabled = isEnabled }


{-| Actual rendering code for the button
-}
viewButton : StyleableButton msg -> Element msg
viewButton (SB data) =
    let
        iconStyle =
            Maybe.map (\s -> [ s ]) data.size |> Maybe.withDefault []

        icon =
            case data.icon of
                Just iconType ->
                    [ Element.el [ Element.moveUp 3 ]
                        (Element.html (FontAwesome.Icon.viewStyled iconStyle iconType))
                    ]

                Nothing ->
                    []

        disabledStyle =
            if data.enabled then
                [ Element.mouseOver [ Background.color data.color.hover ] ]

            else
                [ Font.color data.color.disabledText ]
    in
    button
        ([ padding 5
         , Background.color
            (if data.selected then
                data.color.selected

             else
                data.color.normal
            )
         , Border.rounded 5
         ]
            ++ data.style
            ++ disabledStyle
        )
        { onPress = data.msg
        , label =
            (icon
                ++ [ Element.text data.caption
                   ]
            )
                |> row [ spacing 3, centerX ]
        }
