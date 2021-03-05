module PositionView exposing
    ( BoardDecoration(..)
    , DragPieceData
    , DragState
    , DraggingPieces(..)
    , Highlight(..)
    , InternalModel
    , OpaqueRenderData
    , ViewConfig
    , castingDecoMappers
    , nextHighlight
    , pastMovementIndicatorList
    , render
    , renderStatic
    , staticViewConfig
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
import Colors exposing (ColorOptions)
import Custom.Events as Events exposing (BoardMousePosition)
import Dict
import Element exposing (Element)
import Maybe
import Pieces
import Sako exposing (Piece, Tile(..))
import Svg exposing (Svg)
import Svg.Attributes as SvgA
import Svg.Custom as Svg exposing (BoardRotation, coordinateOfTile)


{-| A representatio of the board where most of the rendering is already done,
but we are still able to interpolate between different stages.

Bikeshedding possible names: Keyframe, ..

-}
type alias OpaqueRenderData =
    { pieces : List VisualPacoPiece
    , rotation : BoardRotation
    }


{-| Given a timeline of render data, we turn it into an actual visual element
respecting the animation that may be running in the timeline.
-}
viewTimeline : ViewConfig a -> Timeline OpaqueRenderData -> Element a
viewTimeline config timeline =
    case Animation.animate timeline of
        Animation.Resting state ->
            viewStatic config state

        Animation.Transition data ->
            animateTransition data
                |> viewStatic config


{-| Renders a position into an intermediate render data object.
-}
render : InternalModel -> Sako.Position -> OpaqueRenderData
render internalModel position =
    { pieces =
        determineVisualPiecesDragged internalModel
            ++ determineVisualPiecesCurrentlyLifted internalModel.rotation internalModel.dragDelta position
            ++ determineVisualPiecesAtRest internalModel.rotation position
    , rotation = internalModel.rotation
    }


{-| If you have a game position where no user input is happening (no drag and
drop, no selection) you can just render this game position directly.
-}
renderStatic : BoardRotation -> Sako.Position -> OpaqueRenderData
renderStatic rotation position =
    { pieces =
        determineVisualPiecesCurrentlyLifted rotation Nothing position
            ++ determineVisualPiecesAtRest rotation position
    , rotation = rotation
    }


viewStatic : ViewConfig msg -> OpaqueRenderData -> Element msg
viewStatic config renderData =
    let
        idAttribute =
            case config.nodeId of
                Just nodeId ->
                    [ SvgA.id nodeId ]

                Nothing ->
                    []

        events =
            [ Maybe.map (Events.svgDown renderData.rotation) config.mouseDown
            , Maybe.map (Events.svgUp renderData.rotation) config.mouseUp
            , Maybe.map (Events.svgMove renderData.rotation) config.mouseMove
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
        [ board renderData.rotation config.colorScheme
        , pastMovementIndicatorLayer renderData.rotation config.decoration
        , castingHighlightLayer renderData.rotation config.decoration
        , highlightLayer renderData.rotation config.decoration
        , dropTargetLayer renderData.rotation config.decoration
        , piecesSvg config.colorScheme renderData.pieces
        , castingArrowLayer renderData.rotation config.decoration
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
    , rotation : BoardRotation
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


type alias ViewConfig msg =
    { colorScheme : ColorOptions
    , nodeId : Maybe String
    , decoration : List BoardDecoration
    , dragPieceData : List DragPieceData
    , mouseDown : Maybe (BoardMousePosition -> msg)
    , mouseUp : Maybe (BoardMousePosition -> msg)
    , mouseMove : Maybe (BoardMousePosition -> msg)
    , additionalSvg : Maybe (Svg msg)
    , replaceViewport : Maybe Svg.Rect
    }


staticViewConfig : ViewConfig msg
staticViewConfig =
    { colorScheme = Colors.configToOptions Colors.defaultBoardColors
    , nodeId = Nothing
    , decoration = []
    , dragPieceData = []
    , mouseDown = Nothing
    , mouseUp = Nothing
    , mouseMove = Nothing
    , additionalSvg = Nothing
    , replaceViewport = Nothing
    }


castingHighlightLayer : BoardRotation -> List BoardDecoration -> Svg a
castingHighlightLayer rotation decorations =
    decorations
        |> List.filterMap getCastingHighlight
        |> List.map (oneCastingDecoTileMarker rotation)
        |> Svg.g []


oneCastingDecoTileMarker : BoardRotation -> Tile -> Svg a
oneCastingDecoTileMarker rotation tile =
    Svg.path
        [ Svg.translate (coordinateOfTile rotation tile)
        , SvgA.d "m 0 0 v 100 h 100 v -100 z"
        , SvgA.fill "rgb(255, 0, 0)"
        ]
        []


castingArrowLayer : BoardRotation -> List BoardDecoration -> Svg a
castingArrowLayer rotation decorations =
    decorations
        |> List.filterMap getCastingArrow
        |> List.reverse
        |> List.map (drawArrow rotation)
        |> Svg.g []


drawArrow : BoardRotation -> Arrow -> Svg a
drawArrow rotation arrow =
    Arrow.toSvg rotation
        [ SvgA.fill "rgb(255, 200, 0, 0.5)"
        ]
        arrow


highlightLayer : BoardRotation -> List BoardDecoration -> Svg a
highlightLayer rotation decorations =
    decorations
        |> List.filterMap getHighlightTile
        |> List.map (highlightSvg rotation)
        |> Svg.g []


pastMovementIndicatorLayer : BoardRotation -> List BoardDecoration -> Svg a
pastMovementIndicatorLayer rotation decorations =
    decorations
        |> List.filterMap getPastMovementIndicator
        |> List.map (onePastMovementIndicator rotation)
        |> Svg.g []


onePastMovementIndicator : BoardRotation -> Tile -> Svg a
onePastMovementIndicator rotation tile =
    Svg.path
        [ Svg.translate (coordinateOfTile rotation tile)
        , SvgA.d "m 0 0 v 100 h 100 v -100 z"
        , SvgA.fill "rgba(255, 255, 0, 0.5)"
        ]
        []


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


highlightSvg : BoardRotation -> ( Tile, Highlight ) -> Svg a
highlightSvg rotation ( tile, highlight ) =
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
        [ Svg.translate (coordinateOfTile rotation tile)
        , shape
        , SvgA.fill "rgb(255, 255, 100)"
        ]
        []


dropTargetLayer : BoardRotation -> List BoardDecoration -> Svg a
dropTargetLayer rotation decorations =
    decorations
        |> List.filterMap getDropTarget
        |> List.map (dropTargetSvg rotation)
        |> Svg.g []


dropTargetSvg : BoardRotation -> Tile -> Svg a
dropTargetSvg rotation tile =
    let
        (Svg.Coord x y) =
            coordinateOfTile rotation tile
    in
    Svg.circle
        [ SvgA.r "20"
        , SvgA.cx (String.fromInt (x + 50))
        , SvgA.cy (String.fromInt (y + 50))
        , SvgA.fill "rgb(200, 200, 200)"
        ]
        []


piecesSvg : ColorOptions -> List VisualPacoPiece -> Svg msg
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


pieceSvg : ColorOptions -> VisualPacoPiece -> Svg msg
pieceSvg colorScheme piece =
    Svg.g [ Svg.translate piece.position, opacity piece.opacity ]
        [ Pieces.figure colorScheme piece.pieceType piece.color ]


opacity : Float -> Svg.Attribute msg
opacity o =
    SvgA.opacity <| String.fromFloat o


board : BoardRotation -> ColorOptions -> Svg msg
board rotation colors =
    Svg.g []
        ([ Svg.rect
            [ SvgA.x "-10"
            , SvgA.y "-10"
            , SvgA.width "820"
            , SvgA.height "820"
            , SvgA.fill colors.borderColor
            ]
            []
         , Svg.rect
            [ SvgA.x "0"
            , SvgA.y "0"
            , SvgA.width "800"
            , SvgA.height "800"
            , SvgA.fill colors.blackTileColor
            ]
            []
         , Svg.path
            [ SvgA.d "M 0,0 H 800 V 100 H 0 Z M 0,200 H 800 V 300 H 0 Z M 0,400 H 800 V 500 H 0 Z M 0,600 H 800 V 700 H 0 Z M 100,0 V 800 H 200 V 0 Z M 300,0 V 800 H 400 V 0 Z M 500,0 V 800 H 600 V 0 Z M 700,0 V 800 H 800 V 0 Z"
            , SvgA.fill colors.whiteTileColor
            ]
            []
         ]
            ++ boardNumbers rotation colors
        )


boardNumbers : BoardRotation -> ColorOptions -> List (Svg a)
boardNumbers rotation colors =
    case rotation of
        Svg.WhiteBottom ->
            [ columnTag "a" "85" colors.whiteTileColor
            , columnTag "b" "185" colors.blackTileColor
            , columnTag "c" "285" colors.whiteTileColor
            , columnTag "d" "385" colors.blackTileColor
            , columnTag "e" "485" colors.whiteTileColor
            , columnTag "f" "585" colors.blackTileColor
            , columnTag "g" "685" colors.whiteTileColor
            , columnTag "h" "785" colors.blackTileColor
            , rowTag "1" "730" colors.whiteTileColor
            , rowTag "2" "630" colors.blackTileColor
            , rowTag "3" "530" colors.whiteTileColor
            , rowTag "4" "430" colors.blackTileColor
            , rowTag "5" "330" colors.whiteTileColor
            , rowTag "6" "230" colors.blackTileColor
            , rowTag "7" "130" colors.whiteTileColor
            , rowTag "8" "30" colors.blackTileColor
            ]

        Svg.BlackBottom ->
            [ columnTag "h" "14" colors.whiteTileColor
            , columnTag "g" "114" colors.blackTileColor
            , columnTag "f" "214" colors.whiteTileColor
            , columnTag "e" "314" colors.blackTileColor
            , columnTag "d" "414" colors.whiteTileColor
            , columnTag "c" "514" colors.blackTileColor
            , columnTag "b" "614" colors.whiteTileColor
            , columnTag "a" "714" colors.blackTileColor
            , rowTag "8" "730" colors.whiteTileColor
            , rowTag "7" "630" colors.blackTileColor
            , rowTag "6" "530" colors.whiteTileColor
            , rowTag "5" "430" colors.blackTileColor
            , rowTag "4" "330" colors.whiteTileColor
            , rowTag "3" "230" colors.blackTileColor
            , rowTag "2" "130" colors.whiteTileColor
            , rowTag "1" "30" colors.blackTileColor
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
    | PastMovementIndicator Tile


{-| This record is used to teach the Decorator module about Board Decorations
without introducing full dependency.
-}
castingDecoMappers : { tile : Tile -> BoardDecoration, arrow : Arrow -> BoardDecoration }
castingDecoMappers =
    { tile = CastingHighlight
    , arrow = CastingArrow
    }


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


getPastMovementIndicator : BoardDecoration -> Maybe Tile
getPastMovementIndicator decoration =
    case decoration of
        PastMovementIndicator tile ->
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



--------------------------------------------------------------------------------
-- Animator specific code ------------------------------------------------------
--------------------------------------------------------------------------------


determineVisualPiecesAtRest : BoardRotation -> Sako.Position -> List VisualPacoPiece
determineVisualPiecesAtRest rotation position =
    position.pieces
        |> List.map
            (\p ->
                { pieceType = p.pieceType
                , color = p.color
                , position = coordinateOfTile rotation p.position
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
determineVisualPiecesCurrentlyLifted : BoardRotation -> Maybe Svg.Coord -> Sako.Position -> List VisualPacoPiece
determineVisualPiecesCurrentlyLifted rotation maybeDragDelta position =
    case position.liftedPieces of
        [ pieceOne, pieceTwo ] ->
            visualPiecesForLiftedPair rotation maybeDragDelta pieceOne pieceTwo

        liftedPieces ->
            List.map (visualPieceCurrentlyLifted rotation maybeDragDelta) liftedPieces


visualPieceCurrentlyLifted : BoardRotation -> Maybe Svg.Coord -> Piece -> VisualPacoPiece
visualPieceCurrentlyLifted rotation dragDelta liftedPiece =
    let
        offset =
            dragDelta
                |> Maybe.withDefault (handCoordinateOffset liftedPiece.color)
    in
    { pieceType = liftedPiece.pieceType
    , color = liftedPiece.color
    , position =
        coordinateOfTile rotation liftedPiece.position
            |> Svg.addCoord offset
    , identity = liftedPiece.identity
    , zOrder = 3
    , opacity = 1
    }


visualPiecesForLiftedPair : BoardRotation -> Maybe Svg.Coord -> Piece -> Piece -> List VisualPacoPiece
visualPiecesForLiftedPair rotation dragDelta pieceOne pieceTwo =
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
            coordinateOfTile rotation pieceOne.position
                |> Svg.addCoord offsetOne
      , identity = pieceOne.identity
      , zOrder = 3
      , opacity = 1
      }
    , { pieceType = pieceTwo.pieceType
      , color = pieceTwo.color
      , position =
            coordinateOfTile rotation pieceTwo.position
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
                                |> Svg.addCoord (coordinateOfTile internalModel.rotation piece.position)
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
                        |> Svg.addCoord (coordinateOfTile internalModel.rotation singlePiece.position)
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
            List.map (\p -> ( p.identity, p )) old.pieces |> Dict.fromList

        newPieces =
            List.map (\p -> ( p.identity, p )) new.pieces |> Dict.fromList

        -- Simple polinomial with derivation 0 at t=0 and t=1.
        smoothT =
            -2 * t ^ 3 + 3 * t ^ 2
    in
    { pieces =
        Dict.merge
            (animateFadeOut smoothT)
            (animateInterpolate smoothT)
            (animateFadeIn smoothT)
            oldPieces
            newPieces
            []
    , rotation = new.rotation
    }


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


{-| The past movement indicator list show what the opponent did in their last
move. If there is nothing to highlight, it just returns an empty list.

The tiles are returned in order, so you are able to identify the lifting tile.

-}
pastMovementIndicatorList : Sako.Position -> List Sako.Action -> List Tile
pastMovementIndicatorList position actions =
    if List.isEmpty position.liftedPieces then
        pastMovementIndicatorListSettled actions

    else
        pastMovementIndicatorListInProcess actions


{-| Given an action list like [Lift 1, Place 1, Place 2, Lift 2, Place 3] this
function returns [Lift 2, Place 3].
-}
pastMovementIndicatorListSettled : List Sako.Action -> List Tile
pastMovementIndicatorListSettled actions =
    List.foldl
        (\a ls ->
            case a of
                Sako.Lift tile ->
                    -- Discard everything and start new when we encounter a lift.
                    [ tile ]

                Sako.Place tile ->
                    tile :: ls

                Sako.Promote _ ->
                    ls
        )
        []
        actions
        |> List.reverse


{-| Given an action list like [Lift 1, Place 1, Place 2, Lift 2, Place 3] this
function returns [Lift 1, Place 1, Place 2].
-}
pastMovementIndicatorListInProcess : List Sako.Action -> List Tile
pastMovementIndicatorListInProcess actions =
    -- This algorithm is basically the same as pastMovementIndicatorListSettled
    -- but we remember the last list we had instead of discarding. So at the end
    -- we just return the remembered list.
    List.foldl
        (\a ( ls1, ls2 ) ->
            case a of
                Sako.Lift tile ->
                    -- Remember the last list and start a new list when we encounter a lift.
                    ( ls2, [ tile ] )

                Sako.Place tile ->
                    ( ls1, tile :: ls2 )

                Sako.Promote _ ->
                    ( ls1, ls2 )
        )
        ( [], [] )
        actions
        |> (\( ls1, _ ) -> ls1)
        |> List.reverse
