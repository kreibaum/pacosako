module Translations exposing (bishop, compiledLanguage, king, knight, pawn, queen, rook, Language(..))

{-| List of all supported languages. Default language is english.
-}
type Language
    = English
    | Dutch
    | Esperanto

compiledLanguage : Language
compiledLanguage =
    English


pawn : String
pawn =
    "Pawn"


rook : String
rook =
    "Rook"


knight : String
knight =
    "Knight"


bishop : String
bishop =
    "Bishop"


queen : String
queen =
    "Queen"


king : String
king =
    "King"
