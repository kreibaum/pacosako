module Tutorial exposing (tutorialPage)

import Browser exposing (element)
import Element exposing (Element, centerX, el, fill, height, maximum, padding, paragraph, scrollbarY, spacing, text, width)
import Element.Background as Background
import Element.Font as Font
import Element.Input as Input
import Embed.Youtube as Youtube
import Embed.Youtube.Attributes as YoutubeA
import I18n.Strings as I18n exposing (I18nToken, Language(..), t)


{-| The tutorial needs only a language and this is stored outside. It contains
the language toggle for now, so it needs to be taught to send language messages.
-}
tutorialPage : Language -> (Language -> msg) -> Element msg
tutorialPage lang langMsg =
    Element.el [ width fill, height fill, scrollbarY ]
        (tutorialPageInner lang langMsg)


tutorialPageInner : Language -> (Language -> msg) -> Element msg
tutorialPageInner lang langMsg =
    Element.column [ width (fill |> maximum 1000), centerX, padding 30, spacing 10 ]
        [ t lang I18n.tutorialHeader
            |> text
            |> el [ Font.size 40, centerX ]
        , paragraph []
            [ t lang I18n.tutorialSummary |> text ]
        , languageToggle lang langMsg
        , oneVideo lang I18n.tutorialSetup
        , oneVideo lang I18n.tutorialMovement
        , oneVideo lang I18n.tutorialFourPacoSakoRules
        , oneVideo lang I18n.tutorialGoal
        , oneVideo lang I18n.tutorialCombosLoopsChains
        , oneVideo lang I18n.tutorialStrategy
        , oneVideo lang I18n.tutorialGamePhases
        , oneVideo lang I18n.tutorialSpecialRules
        , oneVideo lang I18n.tutorialCreativePlayingStyle
        , oneVideo lang I18n.tutorialFunAndBeauty
        ]


languageToggle : Language -> (Language -> msg) -> Element msg
languageToggle lang langMsg =
    case lang of
        English ->
            Input.button [ Font.color (Element.rgb 0 0 1), Font.underline ]
                { onPress = Just (langMsg I18n.Dutch)
                , label = Element.text "Switch to Dutch."
                }

        Dutch ->
            Input.button [ Font.color (Element.rgb 0 0 1), Font.underline ]
                { onPress = Just (langMsg I18n.English)
                , label = Element.text "Switch to English."
                }


oneVideo : Language -> I18nToken ( String, Maybe String ) -> Element msg
oneVideo lang token =
    let
        ( caption, link ) =
            t lang token
    in
    Element.column
        [ width fill
        , height fill
        , spacing 10
        , padding 10
        , Background.color (Element.rgb 0.9 0.9 0.9)
        ]
        [ text caption |> el [ Font.size 25 ]
        , case link of
            Just videoKey ->
                Youtube.fromString videoKey
                    |> Youtube.attributes
                        [ YoutubeA.width 640
                        , YoutubeA.height 400
                        ]
                    |> Youtube.toHtml
                    |> Element.html
                    |> Element.el []

            Nothing ->
                paragraph []
                    [ t lang I18n.tutorialNoVideo |> text ]
        ]
