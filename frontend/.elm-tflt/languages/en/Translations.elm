module Translations exposing (bishop, compiledLanguage, king, knight, pawn, queen, rook)

import I18n.Strings exposing (Language(..))


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
