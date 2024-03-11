module Components exposing
    ( StyleableButton
    , btn
    , colorButton
    , gameCodeLabel
    , grayBox
    , header1
    , header2
    , header3
    , heading
    , iconButton
    , isEnabledIf
    , isSelectedIf
    , paragraph
    , textParagraph
    , viewButton
    , withMsg
    , withMsgIf
    , withSmallIcon
    , withStyle
    )

{-| Module to collect small reusable ui components. Everything in this root module
should not have their own message type or their own complicated data.
-}

import Custom.Element exposing (icon)
import Element exposing (Element, alignRight, centerX, el, fill, height, padding, paddingEach, paddingXY, px, row, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input exposing (button)
import Element.Region exposing (description)
import FontAwesome.Attributes
import FontAwesome.Icon exposing (Icon)
import FontAwesome.Regular as Regular
import Svg


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
    el [ padding 40, centerX, Font.size 40 ] (Element.text caption)


header2 : String -> Element msg
header2 caption =
    el [ Font.size 30 ] (Element.text caption)


header3 : String -> Element msg
header3 caption =
    el [ Font.bold ] (Element.text caption)


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
                    [ el [ Element.moveUp 3 ]
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


gameCodeLabel : msg -> String -> Element msg
gameCodeLabel copyUrlMsg gameKey =
    button
        [ Background.color (Element.rgb255 220 220 220)
        , Element.mouseOver [ Background.color (Element.rgb255 200 200 200) ]
        , width fill
        , Border.rounded 5
        ]
        { onPress = Just copyUrlMsg
        , label =
            Element.row [ height fill, width fill, padding 15, Font.size 40 ]
                [ el [ width fill ] Element.none
                , el [] (Element.text gameKey)
                , el [ width fill, Font.size 30, paddingXY 5 0 ] (icon [ alignRight ] Regular.clipboard)
                ]
        }



--------------------------------------------------------------------------------
-- Below this line we have "2024 Components". Above is older stuff. ------------
--------------------------------------------------------------------------------


{-| A gray box. Good to contain some text. You often want a bunch of these
in a column layout on text heavy pages.
-}
grayBox : List (Element msg) -> Element msg
grayBox content =
    Element.column
        [ width fill
        , Background.color (Element.rgba 1 1 1 0.6)
        , Border.rounded 5
        ]
        content


textParagraph : String -> Element msg
textParagraph content =
    Element.paragraph [ padding 10, Font.justify ] [ text content ]


heading : String -> Element msg
heading content =
    Element.paragraph [ paddingEach { top = 20, right = 10, bottom = 10, left = 10 }, Font.size 25 ]
        [ text content ]


{-| A button with a specific color and an icon. I reacts to hovers with a color change.
-}
colorButton :
    List (Element.Attribute msg)
    ->
        { background : Element.Color
        , backgroundHover : Element.Color
        , onPress : Maybe msg
        , buttonIcon : Element msg
        , caption : String
        }
    -> Element msg
colorButton attrs { background, backgroundHover, onPress, buttonIcon, caption } =
    Input.button
        ([ Background.color background
         , Element.mouseOver [ Background.color backgroundHover ]
         , Border.rounded 5
         ]
            ++ attrs
        )
        { onPress = onPress
        , label =
            Element.row
                [ height fill
                , centerX
                , Element.paddingEach { top = 15, right = 20, bottom = 15, left = 20 }
                , spacing 5
                ]
                [ el [ width (px 20) ] buttonIcon
                , Element.text caption
                ]
        }
