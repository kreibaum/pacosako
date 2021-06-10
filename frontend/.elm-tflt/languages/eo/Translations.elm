module Translations exposing (bishop, compiledLanguage, king, knight, pawn, queen, rook)

import I18n.Strings exposing (Language(..))


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
