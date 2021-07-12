module Header exposing (..)

import Api.LocalStorage exposing (Permission(..))
import Custom.Element exposing (icon)
import Element exposing (Element, fill, height, padding, paragraph, spacing, width)
import Element.Background as Background
import Element.Input as Input
import FontAwesome.Solid as Solid
import FontAwesome.Styles
import Gen.Route as Route exposing (Route)
import I18n.Strings as I18n exposing (t)
import Shared exposing (Msg(..))
import Svg.Custom
import Translations as T exposing (Language(..))


{-| This module contains the page header.
-}
wrapWithHeader : Shared.Model -> (Shared.Msg -> msg) -> Element msg -> Element msg
wrapWithHeader shared toMsg body =
    Element.column [ width fill, height fill, Element.scrollbarY ]
        [ Element.html FontAwesome.Styles.css
        , pageHeader shared Element.none
            |> Element.map toMsg
        , gamesArePublicHint shared
            |> Element.map toMsg
        , body
        ]


{-| Header that is shared by all pages.
-}
pageHeader : Shared.Model -> Element Shared.Msg -> Element Shared.Msg
pageHeader model additionalHeader =
    Element.row [ width fill, Background.color (Element.rgb255 230 230 230) ]
        [ pageHeaderButton Route.Home_ T.headerPlayPacoSako
        , pageHeaderButton Route.Editor T.headerDesignPuzzles
        , pageHeaderButton Route.Tutorial T.headerTutorial
        , additionalHeader
        , languageChoice

        -- login header is disabled, until we get proper registration (oauth)
        --, loginHeaderInfo model model.user
        ]


pageHeaderButton : Route -> String -> Element Shared.Msg
pageHeaderButton route caption =
    Element.link [ padding 10 ]
        { url = Route.toHref route
        , label = Element.text caption
        }


type alias User =
    { id : Int
    , username : String
    }


loginHeaderInfo : Shared.Model -> Maybe User -> Element Shared.Msg
loginHeaderInfo model login =
    let
        loginCaption =
            case login of
                Just user ->
                    Element.row [ padding 10, spacing 10 ] [ icon [] Solid.user, Element.text user.username ]

                Nothing ->
                    Element.row [ padding 10, spacing 10 ] [ icon [] Solid.signInAlt, Element.text T.headerLogin ]
    in
    Element.link [ Element.alignRight ]
        { url = Route.toHref Route.Login
        , label = loginCaption
        }


gamesArePublicHint : Shared.Model -> Element Shared.Msg
gamesArePublicHint model =
    if List.member HideGamesArePublicHint model.permissions then
        Element.none

    else
        Element.row [ width fill, Background.color (Element.rgb255 255 230 230), padding 10 ]
            [ paragraph [ spacing 10 ]
                [ Element.text (t I18n.gamesArePublicHint)
                , Input.button
                    [ Element.alignRight ]
                    { onPress = Just UserHidesGamesArePublicHint
                    , label = Element.text (t I18n.hideGamesArePublicHint)
                    }
                ]
            ]


{-| Allows the user to choose the ui language.
-}
languageChoice : Element Shared.Msg
languageChoice =
    Element.row [ Element.alignRight ]
        [ Input.button [ padding 2 ]
            { onPress = Just (SetLanguage English)
            , label = Svg.Custom.flagEn |> Element.html
            }
        , Input.button [ padding 2 ]
            { onPress = Just (SetLanguage Dutch)
            , label = Svg.Custom.flagNl |> Element.html
            }
        , Input.button [ padding 2 ]
            { onPress = Just (SetLanguage Esperanto)
            , label = Svg.Custom.flagEo |> Element.html
            }
        ]
