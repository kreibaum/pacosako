module Content.References exposing (discordInvite, gitHubLink, officialWebsiteLink, twitchLink)

import Element exposing (Element, centerX, column, el, fill, height, image, maximum, newTabLink, padding, paragraph, px, rgb255, rgba255, row, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
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
                    { src = "/pacosako-logo.png", description = "PacoŜako logo" }
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
