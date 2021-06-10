module Translations exposing (bishop, compiledLanguage, king, knight, pawn, queen, rook, Language(..))

{-| List of all supported languages. Default language is english.
-}
type Language
    = English
    | Dutch
    | Esperanto

compiledLanguage : Language
compiledLanguage =
    Dutch


pawn : String
pawn =
    "Pion"


rook : String
rook =
    "Toren"


knight : String
knight =
    "Paard"


bishop : String
bishop =
    "Loper"


queen : String
queen =
    "Dame"


king : String
king =
    "Koning"
