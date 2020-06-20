module PositionView exposing
    ( BoardDecoration(..)
    , DragPieceData
    , DragState
    , DraggingPieces(..)
    , ExternalMessage
    , Highlight(..)
    , InternalMessage(..)
    , InternalModel
    , OpaqueRenderData
    , PositionViewMsg(..)
    , SvgCoord(..)
    , ViewConfig
    , ViewMode(..)
    , addSvgCoord
    , coordinateOfTile
    , nextHighlight
    , render
    , renderStatic
    , update
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

Here are some notes I wrote during development, likely this will be deleted
before I commit anything.

Note: The hard part will be separating the view model from the data. This model
should not define a datatype that needs to be used instead of the Sako.Position.

I think this means the animation should be managed outside this module. This also
means the animation is a "Timeline Sako.Position" and not (as before) a
"Timeline (List VisualPacoPiece)".

This does mean "rendering" the Board to a List of VisualPacoPiece happens more
often but I hope that won't be a performance bottleneck?

If it is, then I can still have a renderer for a single situation which returns
an opaque object. This opaque object can then be put on a Timeline.

---

Open API improvements:

Highlight should maybe live outside more. I'll have to think about the various
decorations some more.

-}

import Animation exposing (Timeline)
import Dict
import Element exposing (Element)
import EventsCustom as Events exposing (BoardMousePosition)
import Pieces
import Sako exposing (Piece, Tile(..))
import Svg exposing (Svg)
import Svg.Attributes


type alias OpaqueRenderData =
    List VisualPacoPiece


viewTimeline : ViewConfig -> Timeline OpaqueRenderData -> Element PositionViewMsg
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
        ++ renderStatic position


update : PositionViewMsg -> InternalModel -> ( InternalModel, ExternalMessage )
update _ model =
    ( model, () )


{-| If you have a game position where no user input is happening (no drag and
drop, no selection) you can just render this game position directly.
-}
renderStatic : Sako.Position -> OpaqueRenderData
renderStatic position =
    determineVisualPiecesCurrentlyLifted position
        ++ determineVisualPiecesAtRest position


viewStatic : ViewConfig -> OpaqueRenderData -> Element PositionViewMsg
viewStatic config renderData =
    let
        idAttribute =
            case config.nodeId of
                Just nodeId ->
                    [ Svg.Attributes.id nodeId ]

                Nothing ->
                    []

        events =
            if config.withEvents then
                [ Events.svgDown (MouseDown >> InternalMessage)
                , Events.svgMove (MouseMove >> InternalMessage)
                , Events.svgUp (MouseUp >> InternalMessage)
                ]

            else
                []

        attributes =
            [ Svg.Attributes.width <| String.fromInt config.sideLength
            , Svg.Attributes.height <| String.fromInt config.sideLength
            , viewBox (boardViewBox config.viewMode)
            ]
                ++ events
                ++ idAttribute
    in
    Svg.svg attributes
        [ board config.viewMode
        , highlightLayer config.decoration
        , dropTargetLayer config.decoration
        , piecesSvg config.colorScheme renderData
        ]
        |> Element.html


{-| This is everything about the current state of the board the the user of this
module should not need to care about. We need this to render the view and we
update this in response to internal messages.
-}
type alias InternalModel =
    { highlight : Maybe ( Tile, Highlight )
    , dragStartTile : Maybe Tile
    , dragDelta : Maybe SvgCoord
    , hover : Maybe Tile
    , draggingPieces : DraggingPieces
    }


type DraggingPieces
    = DraggingPiecesNormal (List Piece)
    | DraggingPiecesLifted Piece


type PositionViewMsg
    = InternalMessage InternalMessage


type InternalMessage
    = MouseDown BoardMousePosition
    | MouseUp BoardMousePosition
    | MouseMove BoardMousePosition


type alias ExternalMessage =
    ()


{-| A rendered Paco Piece. This must be different from a logical PacoPiece, as
it can be resting, lifted or dragged. The rendering works in two stages where we
first calculate the List VisualPacoPiece and then render those into Svg. In the
render stage we make use of the Animator library.
-}
type alias VisualPacoPiece =
    { pieceType : Sako.Type
    , color : Sako.Color
    , position : SvgCoord
    , identity : String
    , zOrder : Int
    , opacity : Float
    }


type ViewMode
    = ShowNumbers
    | CleanBoard


type alias ViewConfig =
    { sideLength : Int
    , colorScheme : Pieces.ColorScheme
    , viewMode : ViewMode
    , nodeId : Maybe String
    , decoration : List BoardDecoration
    , dragPieceData : List DragPieceData
    , withEvents : Bool
    }


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
                    Svg.Attributes.d "m 0 0 v 100 h 100 v -100 z"

                HighlightWhite ->
                    Svg.Attributes.d "m 0 0 v 100 h 50 v -100 z"

                HighlightBlack ->
                    Svg.Attributes.d "m 50 0 v 100 h 50 v -100 z"

                HighlightLingering ->
                    Svg.Attributes.d "m 50 0 l 50 50 l -50 50 l -50 -50 z"
    in
    Svg.path
        [ translate (coordinateOfTile tile)
        , shape
        , Svg.Attributes.fill "rgb(255, 255, 100)"
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
        [ Svg.Attributes.r "20"
        , Svg.Attributes.cx (String.fromInt (100 * x + 50))
        , Svg.Attributes.cy (String.fromInt (700 - 100 * y + 50))
        , Svg.Attributes.fill "rgb(200, 200, 200)"
        ]
        []


piecesSvg : Pieces.ColorScheme -> List VisualPacoPiece -> Svg msg
piecesSvg colorScheme pieces =
    pieces
        |> List.sortBy .zOrder
        |> List.map (pieceSvg colorScheme)
        |> Svg.g []


handCoordinateOffset : Sako.Color -> SvgCoord
handCoordinateOffset color =
    case color of
        Sako.White ->
            SvgCoord -25 -50

        Sako.Black ->
            SvgCoord 25 -50


pieceSvg : Pieces.ColorScheme -> VisualPacoPiece -> Svg msg
pieceSvg colorScheme piece =
    Svg.g [ translate piece.position, opacity piece.opacity ]
        [ Pieces.figure colorScheme piece.pieceType piece.color ]


{-| A "style='transform: translate(x, y)'" attribute for an svg node.
-}
translate : SvgCoord -> Svg.Attribute msg
translate (SvgCoord x y) =
    Svg.Attributes.style
        ("transform: translate("
            ++ String.fromInt x
            ++ "px, "
            ++ String.fromInt y
            ++ "px)"
        )


opacity : Float -> Svg.Attribute msg
opacity o =
    Svg.Attributes.opacity <| String.fromFloat o


board : ViewMode -> Svg msg
board mode =
    let
        decoration =
            case mode of
                ShowNumbers ->
                    [ columnTag "a" "50"
                    , columnTag "b" "150"
                    , columnTag "c" "250"
                    , columnTag "d" "350"
                    , columnTag "e" "450"
                    , columnTag "f" "550"
                    , columnTag "g" "650"
                    , columnTag "h" "750"
                    , rowTag "1" "770"
                    , rowTag "2" "670"
                    , rowTag "3" "570"
                    , rowTag "4" "470"
                    , rowTag "5" "370"
                    , rowTag "6" "270"
                    , rowTag "7" "170"
                    , rowTag "8" "70"
                    ]

                CleanBoard ->
                    []
    in
    Svg.g []
        ([ Svg.rect
            [ Svg.Attributes.x "-10"
            , Svg.Attributes.y "-10"
            , Svg.Attributes.width "820"
            , Svg.Attributes.height "820"
            , Svg.Attributes.fill "#242"
            ]
            []
         , Svg.rect
            [ Svg.Attributes.x "0"
            , Svg.Attributes.y "0"
            , Svg.Attributes.width "800"
            , Svg.Attributes.height "800"
            , Svg.Attributes.fill "#595"
            ]
            []
         , Svg.path
            [ Svg.Attributes.d "M 0,0 H 800 V 100 H 0 Z M 0,200 H 800 V 300 H 0 Z M 0,400 H 800 V 500 H 0 Z M 0,600 H 800 V 700 H 0 Z M 100,0 V 800 H 200 V 0 Z M 300,0 V 800 H 400 V 0 Z M 500,0 V 800 H 600 V 0 Z M 700,0 V 800 H 800 V 0 Z"
            , Svg.Attributes.fill "#9F9"
            ]
            []
         ]
            ++ decoration
        )


columnTag : String -> String -> Svg msg
columnTag letter x =
    Svg.text_
        [ Svg.Attributes.style "text-anchor:middle;font-size:50px;pointer-events:none;-moz-user-select: none;-webkit-user-select: none;"
        , Svg.Attributes.x x
        , Svg.Attributes.y "870"
        , Svg.Attributes.fill "#555"
        ]
        [ Svg.text letter ]


rowTag : String -> String -> Svg msg
rowTag digit y =
    Svg.text_
        [ Svg.Attributes.style "text-anchor:end;font-size:50px;pointer-events:none;-moz-user-select: none;-webkit-user-select: none;"
        , Svg.Attributes.x "-25"
        , Svg.Attributes.y y
        , Svg.Attributes.fill "#555"
        ]
        [ Svg.text digit ]


type BoardDecoration
    = HighlightTile ( Tile, Highlight )
    | DropTarget Tile


type Highlight
    = HighlightBoth
    | HighlightWhite
    | HighlightBlack
    | HighlightLingering


type alias DragPieceData =
    { color : Sako.Color
    , pieceType : Sako.Type
    , coord : SvgCoord
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
        DropTarget tile ->
            Just tile

        _ ->
            Nothing


type alias DragState =
    Maybe
        { start : BoardMousePosition
        , current : BoardMousePosition
        }


boardViewBox : ViewMode -> Rect
boardViewBox viewMode =
    case viewMode of
        ShowNumbers ->
            { x = -70
            , y = -30
            , width = 900
            , height = 920
            }

        CleanBoard ->
            { x = -30
            , y = -30
            , width = 860
            , height = 860
            }


viewBox : Rect -> Svg.Attribute msg
viewBox rect =
    String.join
        " "
        [ String.fromFloat rect.x
        , String.fromFloat rect.y
        , String.fromFloat rect.width
        , String.fromFloat rect.height
        ]
        |> Svg.Attributes.viewBox


type alias Rect =
    { x : Float
    , y : Float
    , width : Float
    , height : Float
    }



--------------------------------------------------------------------------------
-- Svg Coord type --------------------------------------------------------------
--------------------------------------------------------------------------------


{-| Represents a point in the Svg coordinate space. The game board is rendered from 0 to 800 in
both directions but additional objects are rendered outside.
-}
type SvgCoord
    = SvgCoord Int Int


{-| Add two SVG coordinates, this is applied to each coordinate individually.
-}
addSvgCoord : SvgCoord -> SvgCoord -> SvgCoord
addSvgCoord (SvgCoord x1 y1) (SvgCoord x2 y2) =
    SvgCoord (x1 + x2) (y1 + y2)


{-| Given a logical tile, compute the top left corner coordinates in the svg
coordinate system.
-}
coordinateOfTile : Tile -> SvgCoord
coordinateOfTile (Tile x y) =
    SvgCoord (100 * x) (700 - 100 * y)



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
determineVisualPiecesCurrentlyLifted : Sako.Position -> List VisualPacoPiece
determineVisualPiecesCurrentlyLifted position =
    Maybe.map visualPieceCurrentlyLifted position.liftedPiece
        |> Maybe.map (\p -> [ p ])
        |> Maybe.withDefault []


visualPieceCurrentlyLifted : Piece -> VisualPacoPiece
visualPieceCurrentlyLifted liftedPiece =
    { pieceType = liftedPiece.pieceType
    , color = liftedPiece.color
    , position =
        coordinateOfTile liftedPiece.position
            |> addSvgCoord (handCoordinateOffset liftedPiece.color)
    , identity = liftedPiece.identity
    , zOrder = 3
    , opacity = 1
    }


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
                                |> Maybe.withDefault (SvgCoord 0 0)
                                |> addSvgCoord (coordinateOfTile piece.position)
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
                        |> Maybe.withDefault (SvgCoord 0 0)
                        |> addSvgCoord (coordinateOfTile singlePiece.position)
                        |> addSvgCoord (handCoordinateOffset singlePiece.color)
              , identity = singlePiece.identity
              , zOrder = 3
              , opacity = 1
              }
            ]


animateTransition : { t : Float, old : List VisualPacoPiece, new : List VisualPacoPiece } -> List VisualPacoPiece
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
        (SvgCoord x1 y1) =
            old.position

        (SvgCoord x2 y2) =
            new.position
    in
    { new
        | position =
            SvgCoord
                (round (toFloat x1 * (1 - t) + toFloat x2 * t))
                (round (toFloat y1 * (1 - t) + toFloat y2 * t))
        , zOrder =
            round (toFloat old.zOrder * (1 - t) + toFloat new.zOrder * t)
    }
        :: ls
