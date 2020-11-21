module I18n.Strings exposing
    ( I18nToken
    , Language(..)
    , decodeLanguage
    , encodeLanguage
    , t
    , tutorialCombosLoopsChains
    , tutorialCreativePlayingStyle
    , tutorialFourPacoSakoRules
    , tutorialFunAndBeauty
    , tutorialGamePhases
    , tutorialGoal
    , tutorialHeader
    , tutorialMovement
    , tutorialNoVideo
    , tutorialPageTitle
    , tutorialSetup
    , tutorialSpecialRules
    , tutorialStrategy
    , tutorialSummary
    )

{-| Import is expected as

    import I18n.Strings as I18n exposing (Language(..), t)

-}

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)


{-| List of all supported languages. Default language is english.
-}
type Language
    = English
    | Dutch


encodeLanguage : Language -> Value
encodeLanguage lang =
    case lang of
        English ->
            Encode.string "English"

        Dutch ->
            Encode.string "Dutch"


decodeLanguage : Decoder Language
decodeLanguage =
    Decode.string
        |> Decode.andThen
            (\str ->
                case str of
                    "English" ->
                        Decode.succeed English

                    "Dutch" ->
                        Decode.succeed Dutch

                    otherwise ->
                        Decode.fail ("Language not supported: " ++ otherwise)
            )


{-| Opaque type to represent all language versions of a string.
-}
type I18nToken a
    = I18nToken
        { english : a
        , dutch : a
        }


{-| Extracts a language version from a token. For simple strings, you can use

    t model.lang I18n.tutorialSetup

This function may also return other types depending on the token, so you can
pass in other parameters for some.

    t model.lang I18n.userGreeting model.user

In principle, a translation can have any type. So something like this is
possible as well:

    (t model.lang I18n.flag) : Svg msg

-}
t : Language -> I18nToken a -> a
t lang (I18nToken token) =
    case lang of
        English ->
            token.english

        Dutch ->
            token.dutch



--------------------------------------------------------------------------------
-- Tutorial page ---------------------------------------------------------------
--------------------------------------------------------------------------------


tutorialPageTitle : I18nToken String
tutorialPageTitle =
    I18nToken
        { english = "Learn Paco Ŝako - pacoplay.com"
        , dutch = "Leer Paco Ŝako - pacoplay.com"
        }


tutorialHeader : I18nToken String
tutorialHeader =
    I18nToken
        { english = "Learn Paco Ŝako"
        , dutch = "Leer Paco Ŝako"
        }


tutorialSummary : I18nToken String
tutorialSummary =
    I18nToken
        { english = "Felix is preparing a series of video instructions on Paco Ŝako. You'll be able to find them here and on his Youtube channel. He is doing Dutch first."
        , dutch = "Felix bereidt een reeks video-instructies over Paco Ŝako voor. Je kunt ze hier en op zijn YouTube-kanaal vinden."
        }


tutorialSetup : I18nToken ( String, Maybe String )
tutorialSetup =
    I18nToken
        { english = ( "Setup", Nothing )
        , dutch = ( "Opstelling", Just "1jybatEtdPo" )
        }


tutorialMovement : I18nToken ( String, Maybe String )
tutorialMovement =
    I18nToken
        { english = ( "Movement of the pieces", Nothing )
        , dutch = ( "Beweging van de stukken", Just "mCoara3xUlk" )
        }


tutorialFourPacoSakoRules : I18nToken ( String, Maybe String )
tutorialFourPacoSakoRules =
    I18nToken
        { english = ( "Four Paco Ŝako rules", Nothing )
        , dutch = ( "4 Paco Ŝako Regles", Nothing )
        }


tutorialGoal : I18nToken ( String, Maybe String )
tutorialGoal =
    I18nToken
        { english = ( "Goal of the game", Nothing )
        , dutch = ( "Doel Van Het Spel", Nothing )
        }


tutorialCombosLoopsChains : I18nToken ( String, Maybe String )
tutorialCombosLoopsChains =
    I18nToken
        { english = ( "Combos, loops and chains", Nothing )
        , dutch = ( "Combo's, Loop, Ketting", Nothing )
        }


tutorialStrategy : I18nToken ( String, Maybe String )
tutorialStrategy =
    I18nToken
        { english = ( "Strategy", Nothing )
        , dutch = ( "Strategie", Nothing )
        }


tutorialGamePhases : I18nToken ( String, Maybe String )
tutorialGamePhases =
    I18nToken
        { english = ( "Opening, middlegame, endgame", Nothing )
        , dutch = ( "Opening, Middenspel, Eindspel", Nothing )
        }


tutorialSpecialRules : I18nToken ( String, Maybe String )
tutorialSpecialRules =
    I18nToken
        { english = ( "Castling, promotion, en passant", Nothing )
        , dutch = ( "Rokeren, Promoveren, En Passant", Nothing )
        }


tutorialCreativePlayingStyle : I18nToken ( String, Maybe String )
tutorialCreativePlayingStyle =
    I18nToken
        { english = ( "Creative playing style", Nothing )
        , dutch = ( "Creatieve Speelwijze", Nothing )
        }


tutorialFunAndBeauty : I18nToken ( String, Maybe String )
tutorialFunAndBeauty =
    I18nToken
        { english = ( "Fun and beauty", Nothing )
        , dutch = ( "Spel Plezier & Schoonheid", Nothing )
        }


tutorialNoVideo : I18nToken String
tutorialNoVideo =
    I18nToken
        { english = "Felix is currently preparing this video."
        , dutch = "Felix bereidt momenteel deze video voor."
        }