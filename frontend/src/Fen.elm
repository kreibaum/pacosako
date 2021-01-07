module Fen exposing (PiecesOnTile(..), piecesOnTile)

{-| This module implements an extension of X-Fen that can represent settled Paco
Ŝako boards (i.e. boards without an active chain) together with most state.

It should be mostly compatible with <https://vchess.club/#/variants/Pacosako>
where I got the union notation. There are somewhat different pawn rules on the
vchess.club version, which explains the difference.

-}

import Parser exposing ((|.), (|=), Parser, float, oneOf, spaces, succeed, symbol)
import Sako exposing (Type(..))


type PiecesOnTile
    = SinglePieceOnTile Sako.Type
    | PairOnTile Sako.Type Sako.Type
    | ErrorOnTile


{-| Takes a lower case character and returns which piece this represents. If it
represents a union, returns a list with two entries.

Convention is:
SinglePieceOnTile <black piece type>
PairOnTile <black piece type> <white piece type>

Use an uppercase letter to flip black and white.

-}
piecesOnTile : Char -> PiecesOnTile
piecesOnTile char =
    case char of
        'p' ->
            SinglePieceOnTile Pawn

        'r' ->
            SinglePieceOnTile Rook

        'n' ->
            SinglePieceOnTile Knight

        'b' ->
            SinglePieceOnTile Bishop

        'q' ->
            SinglePieceOnTile Queen

        'k' ->
            SinglePieceOnTile King

        'a' ->
            PairOnTile Pawn Pawn

        'c' ->
            PairOnTile Pawn Rook

        'd' ->
            PairOnTile Pawn Knight

        'e' ->
            PairOnTile Pawn Bishop

        'f' ->
            PairOnTile Pawn Queen

        'g' ->
            PairOnTile Pawn King

        'h' ->
            PairOnTile Rook Rook

        'i' ->
            PairOnTile Rook Knight

        'j' ->
            PairOnTile Rook Bishop

        'l' ->
            PairOnTile Rook Queen

        'm' ->
            PairOnTile Rook King

        'o' ->
            PairOnTile Knight Knight

        's' ->
            PairOnTile Knight Bishop

        't' ->
            PairOnTile Knight Queen

        'u' ->
            PairOnTile Knight King

        'v' ->
            PairOnTile Bishop Bishop

        'w' ->
            PairOnTile Bishop Queen

        'x' ->
            PairOnTile Bishop King

        'y' ->
            PairOnTile Queen Queen

        'z' ->
            PairOnTile Queen King

        '_' ->
            PairOnTile King King

        _ ->
            ErrorOnTile
