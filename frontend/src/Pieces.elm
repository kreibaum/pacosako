module Pieces exposing
    ( ColorScheme
    , SideColor
    , blackPieceColor
    , bluePieceColor
    , colorUi
    , defaultColorScheme
    , figure
    , greenPieceColor
    , orangePieceColor
    , pinkPieceColor
    , purplePieceColor
    , redPieceColor
    , setBlack
    , setWhite
    , whitePieceColor
    , yellowPieceColor
    )

{-| The LICENSE file does not apply to this file!

The svg graphics of Paco Ŝako figures are (c) 2017 Paco Ŝako B.V. and are used by me
with permission from Felix Albers.

This module provides the SVG primitives needed to render a Paco Ŝako board. It
also provides the colors which can be picked.

-}

import Colors exposing (ColorOptions)
import Element
import Sako
import Svg exposing (Attribute, Svg)
import Svg.Attributes exposing (d)


{-| Create an Svg node to represent a single chess figure.

This returns either a path node or a group node containing multiple path nodes.
More complicated figures (e.g. the knight) layer multiple paths and need a group.

-}
figure : ColorOptions -> Sako.Type -> Sako.Color -> Svg msg
figure scheme piece color =
    let
        attributes =
            Svg.Attributes.strokeWidth "2"
                :: Svg.Attributes.strokeLinejoin "round"
                :: colorAttributes scheme color
    in
    figureAttribute piece
        |> List.map (shape attributes)
        |> unify


{-| A side color represents a color combination used by a single player. Each player gets to
choose their own side color. Make sure that the side colors differ.

This is an important feature for Paco Ŝako, as the colorful pieces are even available for purchase
on the Paco Ŝako website.

-}
type alias SideColor =
    { fill : ( Int, Int, Int )
    , stroke : ( Int, Int, Int )
    }


{-| A color Scheme is a combination of two side colors. Make sure that the side colors differ.
-}
type alias ColorScheme =
    { white : SideColor
    , black : SideColor
    }


setWhite : SideColor -> ColorScheme -> ColorScheme
setWhite c s =
    { s | white = c }


setBlack : SideColor -> ColorScheme -> ColorScheme
setBlack c s =
    { s | black = c }


{-| White pieces for the white player, black pieces for the black player.
-}
defaultColorScheme : ColorScheme
defaultColorScheme =
    { white = whitePieceColor
    , black = blackPieceColor
    }


whitePieceColor : SideColor
whitePieceColor =
    { fill = ( 255, 255, 255 ), stroke = ( 0, 0, 0 ) }


redPieceColor : SideColor
redPieceColor =
    { fill = ( 255, 50, 50 ), stroke = ( 150, 50, 50 ) }


orangePieceColor : SideColor
orangePieceColor =
    { fill = ( 255, 150, 50 ), stroke = ( 150, 100, 50 ) }


yellowPieceColor : SideColor
yellowPieceColor =
    { fill = ( 255, 255, 50 ), stroke = ( 150, 150, 50 ) }


greenPieceColor : SideColor
greenPieceColor =
    { fill = ( 50, 255, 50 ), stroke = ( 50, 150, 50 ) }


bluePieceColor : SideColor
bluePieceColor =
    { fill = ( 50, 50, 255 ), stroke = ( 50, 50, 150 ) }


purplePieceColor : SideColor
purplePieceColor =
    { fill = ( 150, 0, 255 ), stroke = ( 140, 0, 150 ) }


pinkPieceColor : SideColor
pinkPieceColor =
    { fill = ( 255, 50, 255 ), stroke = ( 150, 50, 150 ) }


blackPieceColor : SideColor
blackPieceColor =
    { fill = ( 50, 50, 50 ), stroke = ( 0, 0, 0 ) }


blackTransform : Svg.Attribute msg
blackTransform =
    Svg.Attributes.transform "translate(100, 0) scale(-1, 1)"


colorUi : ( Int, Int, Int ) -> Element.Color
colorUi ( r, g, b ) =
    Element.rgb255 r g b


colorAttributes : ColorOptions -> Sako.Color -> List (Svg.Attribute msg)
colorAttributes scheme color =
    case color of
        Sako.White ->
            [ Svg.Attributes.fill scheme.whitePieceFill
            , Svg.Attributes.stroke scheme.whitePieceStroke
            ]

        Sako.Black ->
            [ Svg.Attributes.fill scheme.blackPieceFill
            , Svg.Attributes.stroke scheme.blackPieceStroke
            , blackTransform
            ]


shape : List (Attribute msg) -> Attribute msg -> Svg msg
shape attributes dAttribute =
    Svg.path
        (dAttribute :: attributes)
        []


{-| Groups multiple Svg nodes using a `g` node or returns a plain node if the list only contains
a single element.
-}
unify : List (Svg msg) -> Svg msg
unify elements =
    case elements of
        [ single ] ->
            single

        multiple ->
            Svg.g [] multiple


{-| Return a list of `d` attributes the contains the paths required to render the requested Piece.
Make sure to keep the elements in order!
-}
figureAttribute : Sako.Type -> List (Attribute msg)
figureAttribute piece =
    case piece of
        Sako.Pawn ->
            [ pawn ]

        Sako.Rook ->
            [ rook ]

        Sako.Knight ->
            knight

        Sako.Bishop ->
            [ bishop ]

        Sako.Queen ->
            [ queen ]

        Sako.King ->
            king


pawn : Attribute msg
pawn =
    d "M 26.551366,35.36251 A 17.040858,17.040858 0 0 0 9.5108102,52.403108 17.040858,17.040858 0 0 0 26.551366,69.443631 17.040858,17.040858 0 0 0 43.59297,52.403108 17.040858,17.040858 0 0 0 26.551366,35.36251 Z M 15.446832,72.699071 c -0.636443,0 -1.148673,0.512219 -1.148673,1.148704 v 3.445996 c 0,0.636447 0.51223,1.148666 1.148673,1.148666 h 22.210115 c 0.636443,0 1.14867,-0.512219 1.14867,-1.148666 v -3.445996 c 0,-0.636485 -0.512227,-1.148704 -1.14867,-1.148704 z m 4.567466,11.17157 A 97.222517,97.222517 0 0 0 4.7915121,85.12717 97.222517,97.222517 0 0 0 46.0767,94.455765 97.222517,97.222517 0 0 0 61.299488,93.199273 97.222517,97.222517 0 0 0 20.014298,83.870641 Z"


rook : Attribute msg
rook =
    d "m 8.356095,30.583977 v 35.517211 c 0.05007,1.475841 0.707492,2.557021 2.998783,2.576071 h 30.998109 c 1.403133,-0.0912 2.618372,-0.457819 2.576586,-2.660819 V 30.583977 h -3.12539 v 13.007475 h -4.39198 V 30.583977 H 30.232795 V 43.591452 H 23.221854 V 30.583977 H 15.873465 V 43.591452 H 11.650467 V 30.583977 Z m 5.063773,42.115254 c -0.636443,0 -1.148767,0.51229 -1.148767,1.14877 v 3.44578 c 0,0.63645 0.512324,1.14877 1.148767,1.14877 h 26.770975 c 0.636445,0 1.148768,-0.51232 1.148768,-1.14877 v -3.44578 c 0,-0.63648 -0.512323,-1.14877 -1.148768,-1.14877 z m 6.59443,11.17141 c -5.099362,0.019 -10.188871,0.43935 -15.222327,1.25677 12.909648,6.10374 27.005003,9.28878 41.28482,9.32863 5.099362,-0.019 10.189382,-0.43936 15.222841,-1.25677 -12.909645,-6.10376 -27.005515,-9.28877 -41.285334,-9.32863 z"


knight : List (Attribute msg)
knight =
    [ d "m 24.962006,35.562775 12.826447,-8.42334 c -8.157122,-9.85388 -44.0480342,-0.58564 -24.504261,47.57273 3.315573,8.17 11.677814,-39.14939 11.677814,-39.14939 z"
    , d "m 26.392057,18.766608 c 0,0 -2.109552,6.47342 -3.152777,9.234062 -0.350915,0.92861 -0.161849,1.210712 -2.105817,2.106332 -11.124048,5.12504 -11.713961,21.99333 -10.051065,39.436351 0.284599,2.985328 -0.63191,3.088648 -2.4887371,4.21163 -1.731854,1.047398 -2.3925503,3.374257 -1.2438512,5.743318 H 44.105705 c 0,0 -14.639571,-15.107425 -14.453381,-24.025923 0.150445,-7.206451 6.288667,-0.07671 8.135938,1.436087 1.786858,1.5636 4.15944,2.232525 6.413561,0.574124 2.005811,-1.475708 2.105797,-3.445639 0.861446,-5.6472 -1.14739,-1.280348 -5.269947,-8.570603 -5.455997,-15.219741 -2.871591,-2.775881 -3.590393,-2.329238 -5.162992,-5.714896 -0.657442,-1.415392 -0.836218,-1.747637 -2.59054,-2.134238 -0.969442,-0.213641 -1.323637,-0.06288 -2.105814,-2.105813 -0.997828,-2.606202 -3.355869,-7.894093 -3.355869,-7.894093 z m -6.377905,65.104036 c -5.099363,0.019 -10.189385,0.438832 -15.2228419,1.256255 12.9096479,6.103749 27.0055179,9.288777 41.2853339,9.328628 5.09936,-0.019 10.189382,-0.438845 15.222844,-1.256254 -12.90965,-6.103761 -27.005517,-9.28877 -41.285336,-9.328629 z"
    ]


bishop : Attribute msg
bishop =
    d "m 26.696068,21.204698 c -3.53426,1.506501 -9.4493,6.778101 -2.01022,7.138583 -7.14121,14.131708 -21.89121,31.628378 -6.92981,45.588946 h -5.64875 c -0.8654,0 -1.56218,0.696262 -1.56218,1.561663 v 2.827219 c 0,0.865399 0.69678,1.561661 1.56218,1.561661 h 29.1977 c 0.8654,0 1.56167,-0.696262 1.56167,-1.561661 V 75.49389 c 0,-0.865401 -0.69627,-1.561663 -1.56167,-1.561663 h -5.69681 c 9.40961,-8.0908 7.1197,-18.686478 2.54093,-28.429788 l -7.49618,8.321455 -2.19522,-5.639964 6.78615,-7.977291 c -2.39519,-4.33248 -4.83787,-8.628721 -6.5288,-12.022523 7.3903,-0.476298 2.10367,-5.036357 -2.01899,-6.979418 z m -6.68177,62.665943 c -5.09936,0.019 -10.18938,0.43883 -15.22284,1.25625 12.90965,6.103742 27.00552,9.288782 41.28533,9.328632 5.09936,-0.019 10.18939,-0.43884 15.22285,-1.25625 -12.90965,-6.10376 -27.00552,-9.288772 -41.28534,-9.328632 z"


queen : Attribute msg
queen =
    d "m 27.058698,19.055487 a 4.7786435,4.7786435 0 0 0 -4.77852,4.77903 4.7786435,4.7786435 0 0 0 4.77852,4.77852 4.7786435,4.7786435 0 0 0 4.77852,-4.77852 4.7786435,4.7786435 0 0 0 -4.77852,-4.77903 z m -0.17364,13.08602 -4.91081,11.31094 -5.15834,-9.81801 -2.42931,9.81801 -7.8388,-8.35247 10.2185,37.59926 h -3.42356 c -0.63644,0 -1.14877,0.51228 -1.14877,1.14877 v 3.445786 c 0,0.63644 0.51233,1.14876 1.14877,1.14876 h 27.1203 c 0.63645,0 1.14877,-0.51232 1.14877,-1.14876 v -3.445786 c 0,-0.63649 -0.51232,-1.14877 -1.14877,-1.14877 h -3.26026 l 9.92808,-37.70416 -8.1008,8.45737 -2.42001,-9.82679 -5.09323,9.82679 z m -6.87038,51.729136 c -5.09936,0.019 -10.18939,0.43936 -15.22284,1.25678 12.90965,6.10375 27.005,9.28878 41.28482,9.32862 5.09936,-0.019 10.18938,-0.43935 15.22283,-1.25677 -12.90964,-6.10376 -27.00499,-9.28877 -41.28481,-9.32863 z"


king : List (Attribute msg)
king =
    [ d "m 25.806488,17.925523 c -0.19325,0 -0.3488,0.347548 -0.3488,0.779279 v 1.761649 h -1.88981 c -0.32398,0 -0.58497,0.18007 -0.58497,0.403593 0,0.223525 0.26099,0.403595 0.58497,0.403595 h 1.88981 v 3.201353 h -5.92833 c -0.89879,2e-6 -1.62211,0.723336 -1.62211,1.622123 v 6.666476 c 0,0.89879 0.72332,1.622123 1.62211,1.622123 h 12.51966 c 0.89879,0 1.62211,-0.723333 1.62211,-1.622123 v -6.666476 c 0,-0.898787 -0.72332,-1.622123 -1.62211,-1.622123 h -5.8937 v -3.201353 h 1.92545 c 0.32398,0 0.58447,-0.18007 0.58447,-0.403595 0,-0.223523 -0.26049,-0.403593 -0.58447,-0.403593 h -1.92545 v -1.761649 c 0,-0.431731 -0.15557,-0.779279 -0.34883,-0.779279 z"
    , d "M 13.338792,73.974061 3.2197518,34.291521 H 9.866592 v -3.67063 h 32.043626 v 3.67063 h 6.64684 l -10.21826,40.37699 z"
    , d "m 8.7124818,71.436381 c -0.63644,0 -1.14867,0.51222 -1.14867,1.1487 v 5.41018 c 0,0.63645 0.51223,1.14867 1.14867,1.14867 H 43.128608 c 0.63644,0 1.14867,-0.51222 1.14867,-1.14867 v -5.41018 c 0,-0.63648 -0.51223,-1.1487 -1.14867,-1.1487 z m 11.3018162,12.43426 c -5.099356,0.019 -10.189326,0.43911 -15.2227862,1.25653 12.9096462,6.10374 27.0053662,9.288737 41.2851862,9.328587 5.09936,-0.019 10.18933,-0.43908 15.22279,-1.256487 -12.90965,-6.10376 -27.00537,-9.28877 -41.28519,-9.32863 z"
    , d "m 23.932178,37.992511 c -0.27345,0 -0.4935,0.22058 -0.4935,0.49403 v 5.45548 h -4.64209 c -0.17812,0 -0.32144,0.14332 -0.32144,0.32143 v 4.16357 c 0,0.17811 0.14332,0.32142 0.32144,0.32142 h 4.64209 v 11.20914 c 0,0.27345 0.22005,0.49403 0.4935,0.49403 h 3.51557 c 0.27345,0 0.4935,-0.22058 0.4935,-0.49403 v -11.20914 h 4.84053 c 0.17812,0 0.32144,-0.14331 0.32144,-0.32142 v -4.16357 c 0,-0.17811 -0.14332,-0.32143 -0.32144,-0.32143 h -4.84053 v -5.45548 c 0,-0.27345 -0.22005,-0.49403 -0.4935,-0.49403 z"
    ]
