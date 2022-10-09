module Svg.Twitch exposing (twitchLogo, twitchLogoColor)

import Element exposing (Element)
import Html exposing (text)
import Svg exposing (path, svg)
import Svg.Attributes as SvgAttr


twitchLogoColor : Element.Color
twitchLogoColor =
    Element.rgb255 145 70 255


twitchLogo : Element msg
twitchLogo =
    Element.html
        (svg
            [ SvgAttr.version "1.1"
            , SvgAttr.id "Layer_1"
            , SvgAttr.x "0"
            , SvgAttr.y "0"
            , SvgAttr.viewBox "0 0 2400 2800"
            , SvgAttr.style "enable-background:new 0 0 2400 2800"
            , SvgAttr.xmlSpace "preserve"
            ]
            [ Svg.style []
                [ text ".st1{fill:#9146ff}" ]
            , path
                [ SvgAttr.style "fill:#fff"
                , SvgAttr.d "m2200 1300-400 400h-400l-350 350v-350H600V200h1600z"
                ]
                []
            , Svg.g
                [ SvgAttr.id "Layer_1-2"
                ]
                [ path
                    [ SvgAttr.class "st1"
                    , SvgAttr.d "M500 0 0 500v1800h600v500l500-500h400l900-900V0H500zm1700 1300-400 400h-400l-350 350v-350H600V200h1600v1100z"
                    ]
                    []
                , path
                    [ SvgAttr.class "st1"
                    , SvgAttr.d "M1700 550h200v600h-200zM1150 550h200v600h-200z"
                    ]
                    []
                ]
            ]
        )
