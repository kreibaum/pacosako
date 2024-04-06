module Sako.FenView exposing (viewFenString)

{-| This module should simplify displaying a static view of a board state given
a FEN string.
-}

import Colors
import Element exposing (Element, height, px, width)
import Fen
import PositionView
import Svg.Custom exposing (BoardRotation(..))


viewFenString :
    { fen : String, colorConfig : Colors.ColorConfig, size : Int }
    -> Element msg
viewFenString { fen, colorConfig, size } =
    Fen.parseFen fen
        |> Maybe.map (PositionView.renderStatic WhiteBottom)
        |> Maybe.map (PositionView.viewStatic (PositionView.staticViewConfig colorConfig))
        |> Maybe.map (Element.el [ width (px size), height (px size) ])
        |> Maybe.withDefault Element.none
