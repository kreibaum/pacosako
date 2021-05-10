module Header exposing (..)

import Api.LocalStorage exposing (Permission(..))
import Custom.Element exposing (icon)
import Effect exposing (Effect)
import Element exposing (Element, fill, height, padding, paragraph, spacing, width)
import Element.Background as Background
import Element.Input as Input
import FontAwesome.Solid as Solid
import FontAwesome.Styles
import Gen.Route as Route exposing (Route)
import I18n.Strings as I18n exposing (I18nToken(..), Language(..), t)
import Shared exposing (Msg(..))
import Svg.Custom


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
        [ pageHeaderButton Route.Home_ (t model.language i18nPlayPacoSako)
        , pageHeaderButton Route.Editor (t model.language i18nDesignPuzzles)
        , pageHeaderButton Route.Tutorial (t model.language i18nTutorial)
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
                    Element.row [ padding 10, spacing 10 ] [ icon [] Solid.signInAlt, Element.text (t model.language i18nLogin) ]
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
                [ Element.text (t model.language I18n.gamesArePublicHint)
                , Input.button
                    [ Element.alignRight ]
                    { onPress = Just UserHidesGamesArePublicHint
                    , label = Element.text (t model.language I18n.hideGamesArePublicHint)
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



--------------------------------------------------------------------------------
-- I18n Strings ----------------------------------------------------------------
--------------------------------------------------------------------------------


i18nPlayPacoSako : I18nToken String
i18nPlayPacoSako =
    I18nToken
        { english = "Play Paco Ŝako"
        , dutch = "Speel Paco Ŝako"
        , esperanto = "Ludi Paco Ŝako"
        }


i18nDesignPuzzles : I18nToken String
i18nDesignPuzzles =
    I18nToken
        { english = "Design Puzzles"
        , dutch = "Ontwerp puzzel"
        , esperanto = "Desegni Puzloj"
        }


i18nTutorial : I18nToken String
i18nTutorial =
    I18nToken
        { english = "Tutorial"
        , dutch = "Tutorial"
        , esperanto = "Lernilo"
        }


i18nLogin : I18nToken String
i18nLogin =
    I18nToken
        { english = "Login"
        , dutch = "Log in"
        , esperanto = "Ensaluti"
        }
