module Translations exposing (bishop, compiledLanguage, king, knight, pawn, queen, rook, Language(..))

{-| List of all supported languages. Default language is english.
-}
type Language
    = English
    | Dutch
    | Esperanto
    

compiledLanguage : Language
compiledLanguage =
    Esperanto


pawn : String
pawn =
    "Peono"


rook : String
rook =
    "Turo"


knight : String
knight =
    "Ĉevalo"


bishop : String
bishop =
    "Kuriero"


queen : String
queen =
    "Damo"


king : String
king =
    "Reĝo"
