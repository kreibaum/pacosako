module I18n.Strings exposing
    ( I18nToken(..)
    , Language(..)
    , bishop
    , decodeLanguage
    , encodeLanguage
    , gamesArePublicHint
    , hideGamesArePublicHint
    , king
    , knight
    , pawn
    , queen
    , rook
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
    | Esperanto


encodeLanguage : Language -> Value
encodeLanguage lang =
    case lang of
        English ->
            Encode.string "English"

        Dutch ->
            Encode.string "Dutch"

        Esperanto ->
            Encode.string "Esperanto"


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

                    "Esperanto" ->
                        Decode.succeed Esperanto

                    otherwise ->
                        Decode.fail ("Language not supported: " ++ otherwise)
            )


{-| Opaque type to represent all language versions of a string.
-}
type I18nToken a
    = I18nToken
        { english : a
        , dutch : a
        , esperanto : a
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

        Esperanto ->
            token.esperanto



--------------------------------------------------------------------------------
-- General Paco Ŝako terms -----------------------------------------------------
--------------------------------------------------------------------------------


pawn : I18nToken String
pawn =
    I18nToken
        { english = "Pawn"
        , dutch = "Pion"
        , esperanto = "Peono"
        }


rook : I18nToken String
rook =
    I18nToken
        { english = "Rook"
        , dutch = "Toren"
        , esperanto = "Turo"
        }


knight : I18nToken String
knight =
    I18nToken
        { english = "Knight"
        , dutch = "Paard"
        , esperanto = "Ĉevalo"
        }


bishop : I18nToken String
bishop =
    I18nToken
        { english = "Bishop"
        , dutch = "Loper"
        , esperanto = "Kuriero"
        }


queen : I18nToken String
queen =
    I18nToken
        { english = "Queen"
        , dutch = "Dame"
        , esperanto = "Damo"
        }


king : I18nToken String
king =
    I18nToken
        { english = "King"
        , dutch = "Koning"
        , esperanto = "Reĝo"
        }



--------------------------------------------------------------------------------
-- Shared page -----------------------------------------------------------------
--------------------------------------------------------------------------------


gamesArePublicHint : I18nToken String
gamesArePublicHint =
    I18nToken
        { english = "All games you play are stored indefinitely and publicly available!"
        , dutch = "Alle games die je speelt, worden voor onbepaalde tijd opgeslagen en zijn openbaar beschikbaar!"
        , esperanto = "Ĉiuj ludoj, kiujn vi ludas, estas konservitaj senfine kaj publike haveblaj!"
        }


hideGamesArePublicHint : I18nToken String
hideGamesArePublicHint =
    I18nToken
        { english = "Hide message."
        , dutch = "Bericht verbergen."
        , esperanto = "Kaŝi mesaĝon."
        }



--------------------------------------------------------------------------------
-- Tutorial page ---------------------------------------------------------------
--------------------------------------------------------------------------------


tutorialPageTitle : I18nToken String
tutorialPageTitle =
    I18nToken
        { english = "Learn Paco Ŝako - pacoplay.com"
        , dutch = "Leer Paco Ŝako - pacoplay.com"
        , esperanto = "Lernu Paco Ŝakon - pacoplay.com"
        }


tutorialHeader : I18nToken String
tutorialHeader =
    I18nToken
        { english = "Learn Paco Ŝako"
        , dutch = "Leer Paco Ŝako"
        , esperanto = "Lernu Paco Ŝakon"
        }


tutorialSummary : I18nToken String
tutorialSummary =
    I18nToken
        { english = "Felix is preparing a series of video instructions on Paco Ŝako. You'll be able to find them here and on his Youtube channel. He is doing Dutch first."
        , dutch = "Felix bereidt een reeks video-instructies over Paco Ŝako voor. Je kunt ze hier en op zijn YouTube-kanaal vinden."
        , esperanto = "Ĉi tiu paĝo nur eksistas en la Nederlanda."
        }


tutorialSetup : I18nToken ( String, Maybe String )
tutorialSetup =
    I18nToken
        { english = ( "Setup", Nothing )
        , dutch = ( "Opstelling", Just "1jybatEtdPo" )
        , esperanto = ( "---", Nothing )
        }


tutorialMovement : I18nToken ( String, Maybe String )
tutorialMovement =
    I18nToken
        { english = ( "Movement of the pieces", Nothing )
        , dutch = ( "Beweging van de stukken", Just "mCoara3xUlk" )
        , esperanto = ( "---", Nothing )
        }


tutorialFourPacoSakoRules : I18nToken ( String, Maybe String )
tutorialFourPacoSakoRules =
    I18nToken
        { english = ( "Four Paco Ŝako rules", Nothing )
        , dutch = ( "4 Paco Ŝako Regles", Just "zEq1fqBoL9M" )
        , esperanto = ( "---", Nothing )
        }


tutorialGoal : I18nToken ( String, Maybe String )
tutorialGoal =
    I18nToken
        { english = ( "Goal of the game", Nothing )
        , dutch = ( "Doel Van Het Spel", Nothing )
        , esperanto = ( "---", Nothing )
        }


tutorialCombosLoopsChains : I18nToken ( String, Maybe String )
tutorialCombosLoopsChains =
    I18nToken
        { english = ( "Combos, loops and chains", Nothing )
        , dutch = ( "Combo's, Loop, Ketting", Nothing )
        , esperanto = ( "---", Nothing )
        }


tutorialStrategy : I18nToken ( String, Maybe String )
tutorialStrategy =
    I18nToken
        { english = ( "Strategy", Nothing )
        , dutch = ( "Strategie", Nothing )
        , esperanto = ( "---", Nothing )
        }


tutorialGamePhases : I18nToken ( String, Maybe String )
tutorialGamePhases =
    I18nToken
        { english = ( "Opening, middlegame, endgame", Nothing )
        , dutch = ( "Opening, Middenspel, Eindspel", Nothing )
        , esperanto = ( "---", Nothing )
        }


tutorialSpecialRules : I18nToken ( String, Maybe String )
tutorialSpecialRules =
    I18nToken
        { english = ( "Castling, promotion, en passant", Nothing )
        , dutch = ( "Rokeren, Promoveren, En Passant", Nothing )
        , esperanto = ( "---", Nothing )
        }


tutorialCreativePlayingStyle : I18nToken ( String, Maybe String )
tutorialCreativePlayingStyle =
    I18nToken
        { english = ( "Creative playing style", Nothing )
        , dutch = ( "Creatieve Speelwijze", Nothing )
        , esperanto = ( "---", Nothing )
        }


tutorialFunAndBeauty : I18nToken ( String, Maybe String )
tutorialFunAndBeauty =
    I18nToken
        { english = ( "Fun and beauty", Nothing )
        , dutch = ( "Spel Plezier & Schoonheid", Nothing )
        , esperanto = ( "---", Nothing )
        }


tutorialNoVideo : I18nToken String
tutorialNoVideo =
    I18nToken
        { english = "Felix is currently preparing this video."
        , dutch = "Felix bereidt momenteel deze video voor."
        , esperanto = "Ĉi tiu paĝo nur eksistas en la Nederlanda."
        }
