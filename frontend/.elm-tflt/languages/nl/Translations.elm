module Translations exposing (bishop, compiledLanguage, king, knight, pawn, queen, rook)

import I18n.Strings exposing (Language(..))


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
