module PositionView exposing
    ( BoardDecoration(..)
    , DragPieceData
    , DragState
    , DraggingPieces(..)
    , Highlight(..)
    , InternalModel
    , OpaqueRenderData
    , ViewConfig
    , coordinateOfTile
    , nextHighlight
    , render
    , renderStatic
    , viewStatic
    , viewTimeline
    )

{-| This module handles rendering the board and abstracts the direct user input
into more abstract output messages.

Rendering happens in two phases. In the first phase we turn the abstract
state of the game (a Paco.Position) into an OpaqueRenderData object. In a second
step we turn this opaque value into an SVG.

This two step process with a break in the middle allows us to define animations.
This module can also render a Timeline OpaqueRenderData. Here the timeline is
assembled by the user of the module which retains full controll when the
keyframes should occur. This module will then take care of smoothly
transitioning between the keyframes.

---

Open API improvements:

Highlight should maybe live outside more. I'll have to think about the various
decorations some more.

-}

import Animation exposing (Timeline)
import Arrow exposing (Arrow)
import Dict
import Element exposing (Element)
import EventsCustom as Events exposing (BoardMousePosition)
import Maybe
import Pieces
import Sako exposing (Piece, Tile(..))
import Svg exposing (Svg)
import Svg.Attributes as SvgA
import Svg.Custom as Svg


type alias OpaqueRenderData =
    List VisualPacoPiece


viewTimeline : ViewConfig a -> Timeline OpaqueRenderData -> Element a
viewTimeline config timeline =
    case Animation.animate timeline of
        Animation.Resting state ->
            viewStatic config state

        Animation.Transition data ->
            animateTransition data
                |> viewStatic config


render : InternalModel -> Sako.Position -> OpaqueRenderData
render internalModel position =
    determineVisualPiecesDragged internalModel
        ++ determineVisualPiecesCurrentlyLifted internalModel.dragDelta position
        ++ determineVisualPiecesAtRest position


{-| If you have a game position where no user input is happening (no drag and
drop, no selection) you can just render this game position directly.
-}
renderStatic : Sako.Position -> OpaqueRenderData
renderStatic position =
    determineVisualPiecesCurrentlyLifted Nothing position
        ++ determineVisualPiecesAtRest position


viewStatic : ViewConfig a -> OpaqueRenderData -> Element a
viewStatic config renderData =
    let
        idAttribute =
            case config.nodeId of
                Just nodeId ->
                    [ SvgA.id nodeId ]

                Nothing ->
                    []

        events =
            [ Maybe.map Events.svgDown config.mouseDown
            , Maybe.map Events.svgUp config.mouseUp
            , Maybe.map Events.svgMove config.mouseMove
            ]
                |> List.filterMap (\x -> x)

        attributes =
            [ SvgA.width "100%"
            , SvgA.height "100%"
            , determineViewBox config
            , SvgA.preserveAspectRatio "xMidYMid"
            ]
                ++ events
                ++ idAttribute
    in
    Svg.svg attributes
        [ board
        , castingHighlightLayer config.decoration
        , highlightLayer config.decoration
        , dropTargetLayer config.decoration
        , piecesSvg config.colorScheme renderData
        , castingArrowLayer config.decoration
        , config.additionalSvg
            |> Maybe.withDefault (Svg.g [] [])
        ]
        |> Element.html


{-| This is everything about the current state of the board the the user of this
module should not need to care about. We need this to render the view and we
update this in response to internal messages.
-}
type alias InternalModel =
    { highlight : Maybe ( Tile, Highlight )
    , dragStartTile : Maybe Tile
    , dragDelta : Maybe Svg.Coord
    , hover : Maybe Tile
    , draggingPieces : DraggingPieces
    }


type DraggingPieces
    = DraggingPiecesNormal (List Piece)
    | DraggingPiecesLifted Piece


{-| A rendered Paco Piece. This must be different from a logical PacoPiece, as
it can be resting, lifted or dragged. The rendering works in two stages where we
first calculate the List VisualPacoPiece and then render those into Svg. In the
render stage we make use of the Animator library.
-}
type alias VisualPacoPiece =
    { pieceType : Sako.Type
    , color : Sako.Color
    , position : Svg.Coord
    , identity : String
    , zOrder : Int
    , opacity : Float
    }


type alias ViewConfig a =
    { colorScheme : Pieces.ColorScheme
    , nodeId : Maybe String
    , decoration : List BoardDecoration
    , dragPieceData : List DragPieceData
    , mouseDown : Maybe (BoardMousePosition -> a)
    , mouseUp : Maybe (BoardMousePosition -> a)
    , mouseMove : Maybe (BoardMousePosition -> a)
    , additionalSvg : Maybe (Svg a)
    , replaceViewport : Maybe Svg.Rect
    }


castingHighlightLayer : List BoardDecoration -> Svg a
castingHighlightLayer decorations =
    decorations
        |> List.filterMap getCastingHighlight
        |> List.map oneCastingDecoTileMarker
        |> Svg.g []


oneCastingDecoTileMarker : Tile -> Svg a
oneCastingDecoTileMarker tile =
    Svg.path
        [ Svg.translate (coordinateOfTile tile)
        , SvgA.d "m 0 0 v 100 h 100 v -100 z"
        , SvgA.fill "rgb(255, 0, 0)"
        ]
        []


castingArrowLayer : List BoardDecoration -> Svg a
castingArrowLayer decorations =
    decorations
        |> List.filterMap getCastingArrow
        |> List.reverse
        |> List.map drawArrow
        |> Svg.g []


drawArrow : Arrow -> Svg a
drawArrow arrow =
    Arrow.toSvg
        [ SvgA.fill "rgb(255, 200, 0)"
        , SvgA.strokeLinejoin "round"
        , SvgA.stroke "black"
        , SvgA.strokeWidth "2"
        ]
        arrow


highlightLayer : List BoardDecoration -> Svg a
highlightLayer decorations =
    decorations
        |> List.filterMap getHighlightTile
        |> List.map highlightSvg
        |> Svg.g []


nextHighlight : Tile -> Maybe ( Tile, Highlight ) -> Maybe ( Tile, Highlight )
nextHighlight newTile maybeHighlight =
    case maybeHighlight of
        Nothing ->
            Just ( newTile, HighlightBoth )

        Just ( oldTile, HighlightBoth ) ->
            if oldTile == newTile then
                Just ( oldTile, HighlightWhite )

            else
                Just ( newTile, HighlightBoth )

        Just ( oldTile, HighlightWhite ) ->
            if oldTile == newTile then
                Just ( oldTile, HighlightBlack )

            else
                Just ( newTile, HighlightBoth )

        Just ( oldTile, HighlightBlack ) ->
            if oldTile == newTile then
                Nothing

            else
                Just ( newTile, HighlightBoth )

        Just ( oldTile, HighlightLingering ) ->
            if oldTile == newTile then
                Just ( oldTile, HighlightBoth )

            else
                Just ( newTile, HighlightBoth )


highlightSvg : ( Tile, Highlight ) -> Svg a
highlightSvg ( tile, highlight ) =
    let
        shape =
            case highlight of
                HighlightBoth ->
                    SvgA.d "m 0 0 v 100 h 100 v -100 z"

                HighlightWhite ->
                    SvgA.d "m 0 0 v 100 h 50 v -100 z"

                HighlightBlack ->
                    SvgA.d "m 50 0 v 100 h 50 v -100 z"

                HighlightLingering ->
                    SvgA.d "m 50 0 l 50 50 l -50 50 l -50 -50 z"
    in
    Svg.path
        [ Svg.translate (coordinateOfTile tile)
        , shape
        , SvgA.fill "rgb(255, 255, 100)"
        ]
        []


dropTargetLayer : List BoardDecoration -> Svg a
dropTargetLayer decorations =
    decorations
        |> List.filterMap getDropTarget
        |> List.map dropTargetSvg
        |> Svg.g []


dropTargetSvg : Tile -> Svg a
dropTargetSvg (Tile x y) =
    Svg.circle
        [ SvgA.r "20"
        , SvgA.cx (String.fromInt (100 * x + 50))
        , SvgA.cy (String.fromInt (700 - 100 * y + 50))
        , SvgA.fill "rgb(200, 200, 200)"
        ]
        []


piecesSvg : Pieces.ColorScheme -> List VisualPacoPiece -> Svg msg
piecesSvg colorScheme pieces =
    pieces
        |> List.sortBy .zOrder
        |> List.map (pieceSvg colorScheme)
        |> Svg.g []


handCoordinateOffset : Sako.Color -> Svg.Coord
handCoordinateOffset color =
    case color of
        Sako.White ->
            Svg.Coord -25 -50

        Sako.Black ->
            Svg.Coord 25 -50


pieceSvg : Pieces.ColorScheme -> VisualPacoPiece -> Svg msg
pieceSvg colorScheme piece =
    Svg.g [ Svg.translate piece.position, opacity piece.opacity ]
        [ Pieces.figure colorScheme piece.pieceType piece.color ]


opacity : Float -> Svg.Attribute msg
opacity o =
    SvgA.opacity <| String.fromFloat o


board : Svg msg
board =
    Svg.g []
        ([ Svg.rect
            [ SvgA.x "-10"
            , SvgA.y "-10"
            , SvgA.width "820"
            , SvgA.height "820"
            , SvgA.fill "#242"
            ]
            []
         , Svg.rect
            [ SvgA.x "0"
            , SvgA.y "0"
            , SvgA.width "800"
            , SvgA.height "800"
            , SvgA.fill "#595"
            ]
            []
         , Svg.path
            [ SvgA.d "M 0,0 H 800 V 100 H 0 Z M 0,200 H 800 V 300 H 0 Z M 0,400 H 800 V 500 H 0 Z M 0,600 H 800 V 700 H 0 Z M 100,0 V 800 H 200 V 0 Z M 300,0 V 800 H 400 V 0 Z M 500,0 V 800 H 600 V 0 Z M 700,0 V 800 H 800 V 0 Z"
            , SvgA.fill "#9F9"
            ]
            []
         ]
            ++ boardNumbers
        )


boardNumbers : List (Svg a)
boardNumbers =
    [ columnTag "a" "85" "#9F9"
    , columnTag "b" "185" "#595"
    , columnTag "c" "285" "#9F9"
    , columnTag "d" "385" "#595"
    , columnTag "e" "485" "#9F9"
    , columnTag "f" "585" "#595"
    , columnTag "g" "685" "#9F9"
    , columnTag "h" "785" "#595"
    , rowTag "1" "730" "#9F9"
    , rowTag "2" "630" "#595"
    , rowTag "3" "530" "#9F9"
    , rowTag "4" "430" "#595"
    , rowTag "5" "330" "#9F9"
    , rowTag "6" "230" "#595"
    , rowTag "7" "130" "#9F9"
    , rowTag "8" "30" "#595"
    ]


columnTag : String -> String -> String -> Svg msg
columnTag letter x color =
    Svg.text_
        [ SvgA.style "text-anchor:middle;font-size:30px;pointer-events:none;-moz-user-select: none;-webkit-user-select: none;"
        , SvgA.x x
        , SvgA.y "793"
        , SvgA.fill color
        ]
        [ Svg.text letter ]


rowTag : String -> String -> String -> Svg msg
rowTag digit y color =
    Svg.text_
        [ SvgA.style "text-anchor:end;font-size:30px;pointer-events:none;-moz-user-select: none;-webkit-user-select: none;"
        , SvgA.x "22"
        , SvgA.y y
        , SvgA.fill color
        ]
        [ Svg.text digit ]


type BoardDecoration
    = HighlightTile ( Tile, Highlight )
    | PlaceTarget Tile
    | CastingHighlight Tile
    | CastingArrow Arrow


type Highlight
    = HighlightBoth
    | HighlightWhite
    | HighlightBlack
    | HighlightLingering


type alias DragPieceData =
    { color : Sako.Color
    , pieceType : Sako.Type
    , coord : Svg.Coord
    , identity : String
    }


getHighlightTile : BoardDecoration -> Maybe ( Tile, Highlight )
getHighlightTile decoration =
    case decoration of
        HighlightTile ( tile, highlight ) ->
            Just ( tile, highlight )

        _ ->
            Nothing


getDropTarget : BoardDecoration -> Maybe Tile
getDropTarget decoration =
    case decoration of
        PlaceTarget tile ->
            Just tile

        _ ->
            Nothing


getCastingHighlight : BoardDecoration -> Maybe Tile
getCastingHighlight decoration =
    case decoration of
        CastingHighlight tile ->
            Just tile

        _ ->
            Nothing


getCastingArrow : BoardDecoration -> Maybe Arrow
getCastingArrow decoration =
    case decoration of
        CastingArrow tile ->
            Just tile

        _ ->
            Nothing


type alias DragState =
    Maybe
        { start : BoardMousePosition
        , current : BoardMousePosition
        }


boardViewBox : Svg.Rect
boardViewBox =
    { x = -30
    , y = -30
    , width = 860
    , height = 860
    }


determineViewBox : ViewConfig a -> Svg.Attribute msg
determineViewBox config =
    config.replaceViewport
        |> Maybe.withDefault boardViewBox
        |> Svg.makeViewBox


{-| Given a logical tile, compute the top left corner coordinates in the svg
coordinate system.
-}
coordinateOfTile : Tile -> Svg.Coord
coordinateOfTile (Tile x y) =
    Svg.Coord (100 * x) (700 - 100 * y)



--------------------------------------------------------------------------------
-- Animator specific code ------------------------------------------------------
--------------------------------------------------------------------------------


determineVisualPiecesAtRest : Sako.Position -> List VisualPacoPiece
determineVisualPiecesAtRest position =
    position.pieces
        |> List.map
            (\p ->
                { pieceType = p.pieceType
                , color = p.color
                , position = coordinateOfTile p.position
                , identity = p.identity
                , zOrder = restingZOrder p.color
                , opacity = 1
                }
            )


restingZOrder : Sako.Color -> Int
restingZOrder color =
    case color of
        Sako.Black ->
            1

        Sako.White ->
            2


{-| Here we return List a instead of Maybe a to allow easier combination with
other lists.
-}
determineVisualPiecesCurrentlyLifted : Maybe Svg.Coord -> Sako.Position -> List VisualPacoPiece
determineVisualPiecesCurrentlyLifted maybeDragDelta position =
    case position.liftedPieces of
        [ pieceOne, pieceTwo ] ->
            visualPiecesForLiftedPair maybeDragDelta pieceOne pieceTwo

        liftedPieces ->
            List.map (visualPieceCurrentlyLifted maybeDragDelta) liftedPieces


visualPieceCurrentlyLifted : Maybe Svg.Coord -> Piece -> VisualPacoPiece
visualPieceCurrentlyLifted dragDelta liftedPiece =
    let
        offset =
            dragDelta
                |> Maybe.withDefault (handCoordinateOffset liftedPiece.color)
    in
    { pieceType = liftedPiece.pieceType
    , color = liftedPiece.color
    , position =
        coordinateOfTile liftedPiece.position
            |> Svg.addCoord offset
    , identity = liftedPiece.identity
    , zOrder = 3
    , opacity = 1
    }


visualPiecesForLiftedPair : Maybe Svg.Coord -> Piece -> Piece -> List VisualPacoPiece
visualPiecesForLiftedPair dragDelta pieceOne pieceTwo =
    let
        offsetOne =
            dragDelta
                |> Maybe.withDefault (Svg.Coord 0 -50)

        offsetTwo =
            dragDelta
                |> Maybe.withDefault (Svg.Coord 0 -50)
    in
    [ { pieceType = pieceOne.pieceType
      , color = pieceOne.color
      , position =
            coordinateOfTile pieceOne.position
                |> Svg.addCoord offsetOne
      , identity = pieceOne.identity
      , zOrder = 3
      , opacity = 1
      }
    , { pieceType = pieceTwo.pieceType
      , color = pieceTwo.color
      , position =
            coordinateOfTile pieceTwo.position
                |> Svg.addCoord offsetTwo
      , identity = pieceTwo.identity
      , zOrder = 3
      , opacity = 1
      }
    ]


{-| TODO Deprecated: Externally tracking which pieces need to be dragged is
outdated. Instead, the drag delta will be applied to all lifted pieces.
-}
determineVisualPiecesDragged : InternalModel -> List VisualPacoPiece
determineVisualPiecesDragged internalModel =
    case internalModel.draggingPieces of
        DraggingPiecesNormal pieceList ->
            pieceList
                |> List.map
                    (\piece ->
                        { pieceType = piece.pieceType
                        , color = piece.color
                        , position =
                            internalModel.dragDelta
                                |> Maybe.withDefault (Svg.Coord 0 0)
                                |> Svg.addCoord (coordinateOfTile piece.position)
                        , identity = piece.identity
                        , zOrder = 3
                        , opacity = 1
                        }
                    )

        DraggingPiecesLifted singlePiece ->
            [ { pieceType = singlePiece.pieceType
              , color = singlePiece.color
              , position =
                    internalModel.dragDelta
                        |> Maybe.withDefault (Svg.Coord 0 0)
                        |> Svg.addCoord (coordinateOfTile singlePiece.position)
                        |> Svg.addCoord (handCoordinateOffset singlePiece.color)
              , identity = singlePiece.identity
              , zOrder = 3
              , opacity = 1
              }
            ]


animateTransition : { t : Float, old : OpaqueRenderData, new : OpaqueRenderData } -> OpaqueRenderData
animateTransition { t, old, new } =
    let
        oldPieces =
            List.map (\p -> ( p.identity, p )) old |> Dict.fromList

        newPieces =
            List.map (\p -> ( p.identity, p )) new |> Dict.fromList

        -- Simple polinomial with derivation 0 at t=0 and t=1.
        smoothT =
            -2 * t ^ 3 + 3 * t ^ 2
    in
    Dict.merge
        (animateFadeOut smoothT)
        (animateInterpolate smoothT)
        (animateFadeIn smoothT)
        oldPieces
        newPieces
        []


animateFadeOut : Float -> a -> VisualPacoPiece -> List VisualPacoPiece -> List VisualPacoPiece
animateFadeOut t _ piece ls =
    { piece | opacity = 1 - t } :: ls


animateFadeIn : Float -> a -> VisualPacoPiece -> List VisualPacoPiece -> List VisualPacoPiece
animateFadeIn t _ piece ls =
    { piece | opacity = t } :: ls


animateInterpolate : Float -> a -> VisualPacoPiece -> VisualPacoPiece -> List VisualPacoPiece -> List VisualPacoPiece
animateInterpolate t _ old new ls =
    let
        (Svg.Coord x1 y1) =
            old.position

        (Svg.Coord x2 y2) =
            new.position
    in
    { new
        | position =
            Svg.Coord
                (round (toFloat x1 * (1 - t) + toFloat x2 * t))
                (round (toFloat y1 * (1 - t) + toFloat y2 * t))
        , zOrder =
            round (toFloat old.zOrder * (1 - t) + toFloat new.zOrder * t)
    }
        :: ls
