module Content.References exposing (discordInvite, gitHubLink, officialWebsiteLink, posterumCupInvite, twitchLink, translationSuggestion)

import Element exposing (Element, centerX, clip, column, el, fill, height, image, maximum, newTabLink, padding, paragraph, px, rgba255, row, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Header exposing (flagForLanguage)
import StaticAssets
import Svg.Discord
import Svg.Github
import Svg.Twitch
import Translations as T


smallBanner :
    { url : String
    , label : Element msg
    }
    -> Element msg
smallBanner data =
    el [ width fill, height fill ]
        (newTabLink [ width fill, height fill, centerX, padding 10, Background.color (rgba255 255 255 255 0.6), Border.rounded 5 ]
            data
        )


discordInvite : Element msg
discordInvite =
    smallBanner
        { url = "https://discord.gg/tFgD5Qf8jB"
        , label =
            column [ width fill, centerX, spacing 7 ]
                [ el [ width (fill |> maximum 400), padding 10, centerX ] Svg.Discord.discordLogo
                , el
                    [ Font.color Svg.Discord.discordLogoColor
                    , Font.size 25
                    , centerX
                    ]
                    (paragraph [] [ text T.communityJoinOnDiscord ])
                ]
        }


officialWebsiteLink : Element msg
officialWebsiteLink =
    smallBanner
        { url = T.communityOfficialWebsiteLink
        , label =
            column [ width fill, centerX, spacing 7 ]
                [ image [ width (fill |> maximum 400), centerX ]
                    { src = StaticAssets.pacosakoLogo, description = "PacoŜako logo" }
                , el
                    [ Font.size 25
                    , centerX
                    ]
                    (paragraph [] [ text T.communityOfficialWebsite ])
                ]
        }


twitchLink : Element msg
twitchLink =
    smallBanner
        { url = "https://www.twitch.tv/pacosako"
        , label =
            row [ width fill, centerX, spacing 5 ]
                [ el [ width (px 50), padding 10, centerX ] Svg.Twitch.twitchLogo
                , el
                    [ Font.color Svg.Twitch.twitchLogoColor
                    , Font.size 25
                    , centerX
                    ]
                    (paragraph [] [ text T.communityWatchOnTwitch ])
                ]
        }


gitHubLink : Element msg
gitHubLink =
    smallBanner
        { url = "https://github.com/kreibaum/pacosako"
        , label =
            row [ width fill, centerX, spacing 5 ]
                [ el [ width (px 50), padding 10, centerX ] Svg.Github.gitHubLogo
                , el
                    [ Font.size 25
                    , centerX
                    ]
                    (paragraph [] [ text T.communityStarOnGithub ])
                ]
        }


posterumCupInvite : Element msg
posterumCupInvite =
    el [ width fill, height fill ]
        (newTabLink [ width fill, height fill, centerX, Border.rounded 5 ]
            { url = "https://forms.gle/iBrXyrfKyUvx4WK48"
            , label =
                image [ width fill, Border.rounded 5, clip ]
                    { src = StaticAssets.pspcPacoplayBanner, description = "An invitation to join the Paco Sako Posterum Cup. The competition is taking place on 6th April 2025." }
            }
        )

translationSuggestion : Element msg
translationSuggestion =
    let
        translationPercent = 100.0 * toFloat T.translatedKeys / toFloat T.totalKeys |> truncate
    in
    if translationPercent < 100 then
        smallBanner
            { url = "https://hosted.weblate.org/engage/pacoplay/"
            , label =
                row [ width fill, centerX, spacing 5 ]
                    [ el [ width (px 50), padding 10, centerX ]
                        (flagForLanguage T.compiledLanguage)
                    , el
                        [ Font.size 25
                        , centerX, width fill
                        ]
                        (paragraph [ width fill ] [ T.translationNotComplete
                            |> String.replace "{0}" (String.fromInt translationPercent)
                            |> text ])
                    ]
            }
    else
        Element.none