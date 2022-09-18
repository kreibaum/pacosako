module Header exposing (..)

{-| This module contains the page header.
-}

import Api.LocalStorage exposing (Permission(..))
import Custom.Element exposing (icon)
import Element exposing (Element, alignRight, centerX, el, fill, height, padding, paragraph, px, spacing, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import FontAwesome.Solid as Solid
import FontAwesome.Styles
import Gen.Route as Route exposing (Route)
import Shared exposing (Msg(..))
import Svg.Custom
import Translations as T exposing (Language(..))


{-| Given a page, puts the header on it.
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
        , pageHeaderButton Route.Tutorial T.headerTutorial
        , pageHeaderButton Route.Editor T.headerDesignPuzzles
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
                [ Element.text T.gamesArePublicHint
                , Input.button
                    [ Element.alignRight ]
                    { onPress = Just UserHidesGamesArePublicHint
                    , label = Element.text T.hideGamesArePublicHint
                    }
                ]
            ]


{-| Allows the user to choose the ui language.
-}
languageChoice : Element Shared.Msg
languageChoice =
    Element.row [ alignRight ]
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



---- V2


type alias HeaderData =
    { isRouteHighlighted : Route -> Bool
    , isWithBackground : Bool
    }


{-| Header for the refactored ui.
-}
wrapWithHeaderV2 : Shared.Model -> (Shared.Msg -> msg) -> HeaderData -> Element msg -> Element msg
wrapWithHeaderV2 shared toMsg headerData body =
    Element.column
        [ width fill
        , height fill
        , Element.scrollbarY
        , if headerData.isWithBackground then
            Background.image "/bg.jpg"

          else
            Background.color (Element.rgb255 255 255 255)
        ]
        [ Element.html FontAwesome.Styles.css
        , pageHeaderV2 shared headerData
            |> Element.map toMsg
        , gamesArePublicHint shared
            |> Element.map toMsg
        , body
        ]


{-| Header that is shared by all pages.

TODO: Make this reactive for small devices and put a hamburger menu on the left.

-}
pageHeaderV2 : Shared.Model -> HeaderData -> Element Shared.Msg
pageHeaderV2 model headerData =
    Element.row
        [ width fill
        , Border.solid
        , Border.widthEach
            { bottom = 1
            , left = 0
            , right = 0
            , top = 0
            }
        , Border.color (Element.rgb255 200 200 200)
        , Background.color (Element.rgba255 255 255 255 0.6)
        ]
        [ Element.row
            [ width (Element.maximum 1120 fill)
            , centerX
            , Element.paddingXY 10 20
            , spacing 5
            ]
            [ Element.row [ spacing 15, width fill ]
                [ pageHeaderButtonV2 Route.Home_ T.headerPlayPacoSako headerData.isRouteHighlighted
                , pageHeaderButtonV2 Route.Tutorial T.headerTutorial headerData.isRouteHighlighted
                , pageHeaderButtonV2 Route.Editor T.headerDesignPuzzles headerData.isRouteHighlighted
                ]
            , el [] pacosakoLogo
            , el [ width fill ] languageChoiceV2
            ]
        ]


pageHeaderButtonV2 : Route -> String -> (Route -> Bool) -> Element Shared.Msg
pageHeaderButtonV2 route caption isRouteHighlighted =
    Element.link (pageHeaderStyle (isRouteHighlighted route))
        { url = Route.toHref route
        , label = Element.text caption
        }


pageHeaderStyle : Bool -> List (Element.Attribute msg)
pageHeaderStyle isRouteHighlighted =
    if isRouteHighlighted then
        [ Font.color (Element.rgb255 0 0 0)
        , Font.bold
        ]

    else
        [ Font.color (Element.rgb255 150 150 150)
        , Element.mouseOver [ Font.color (Element.rgb255 70 70 70) ]
        , Font.bold
        ]


pacosakoLogo : Element msg
pacosakoLogo =
    Element.image [ width (px 150), centerX ]
        { src = "/pacosako-logo.png", description = "PacoŜako logo" }


{-| Allows the user to choose the ui language.
-}
languageChoiceV2 : Element Shared.Msg
languageChoiceV2 =
    Element.row [ alignRight ]
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
        , Input.button [ padding 2 ]
            { onPress = Just (SetLanguage Swedish)
            , label = Svg.Custom.flagSv |> Element.html
            }
        , Input.button [ padding 2 ]
            { onPress = Just (SetLanguage German)
            , label = Svg.Custom.flagDe |> Element.html
            }
        ]
