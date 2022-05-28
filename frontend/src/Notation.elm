module Notation exposing
    ( ConsensedActionKey
    , NotationAtom(..)
    , SidebarMoveData
    , compile
    , firstActionCountAfterIndex
    , lastAction
    , lastActionCountBefore
    , lastActionCountBeforeIndex
    , lastActionCountOf
    , moveContainingAction
    , writeOut
    )

{-| Implements Paco Ŝako Style Notation.

In our first incarnation we'll not simplify the squares and instead always give full coordinates.

-}

import Api.Backend as Backend
import Custom.List as List
import List.Extra as List
import Sako


compile : Backend.Replay -> List SidebarMoveData
compile replay =
    breakHistoryIntoMoves replay.actions
        |> translateActionsToNotation Sako.initialPosition
        |> List.map condenseMoveNotation


{-| A notation atom roughly corresponds to a Sako.Action but carries more metadata.
-}
type NotationAtom
    = StartMoveSingle Sako.Type Sako.Tile
    | StartMoveUnion Sako.Type Sako.Type Sako.Tile
    | ContinueChain Sako.Type Sako.Tile
    | EndMoveCalm Sako.Tile
    | EndMoveFormUnion Sako.Type Sako.Tile
    | Promote Sako.Type
    | NotationError String


{-| Data required to show a single move in the sidebar.
-}
type alias SidebarMoveData =
    { moveNumber : Int
    , color : Sako.Color
    , actions : List ConsensedActionKey
    }


lastAction : List SidebarMoveData -> Int
lastAction moves =
    List.last moves
        |> Maybe.map lastActionCountOf
        |> Maybe.withDefault 0


{-| Given a move, returns the action count of the last action in in. If the
move is invalid (i.e. has no actions) then -42 is returned instead.
-}
lastActionCountOf : SidebarMoveData -> Int
lastActionCountOf data =
    List.last data.actions
        |> Maybe.map .actionIndex
        |> Maybe.withDefault -42


{-| Given a move, returns the action count of the first action in in. If the
move is invalid (i.e. has no actions) then -42 is returned instead.
-}
firstActionCountOf : SidebarMoveData -> Int
firstActionCountOf data =
    List.head data.actions
        |> Maybe.map .actionIndex
        |> Maybe.withDefault -42


{-| Given a move, returns the action count right before this move.
This is the lastActionCountOf the previous move.
-}
lastActionCountBefore : SidebarMoveData -> Int
lastActionCountBefore data =
    List.head data.actions
        |> Maybe.map (\cak -> cak.actionIndex - List.length cak.actions)
        |> Maybe.withDefault -42


{-| Finds the first action count that is represented by a ConsensedActionKey
with an action index higher than the given index.
-}
firstActionCountAfterIndex : Int -> List SidebarMoveData -> Maybe Int
firstActionCountAfterIndex index moves =
    List.findMap (firstActionCountAfterInternal index) moves


firstActionCountAfterInternal : Int -> SidebarMoveData -> Maybe Int
firstActionCountAfterInternal index move =
    List.find (\cak -> cak.actionIndex > index) move.actions
        |> Maybe.map .actionIndex


lastActionCountBeforeIndex : Int -> List SidebarMoveData -> Int
lastActionCountBeforeIndex index move =
    List.takeWhile (\smd -> firstActionCountOf smd < index) move
        |> List.last
        |> Maybe.andThen
            (\smd ->
                List.takeWhile (\cak -> cak.actionIndex < index) smd.actions
                    |> List.last
                    |> Maybe.map .actionIndex
            )
        |> Maybe.withDefault 0


moveContainingAction : Int -> List SidebarMoveData -> Maybe SidebarMoveData
moveContainingAction index moves =
    List.dropWhile (\smd -> lastActionCountOf smd < index) moves
        |> List.head


{-| Combines the first two actions into a single one, so the lift and the first
place are always combined.

This is more a ui think to make the replay nicer.

-}
condenseMoveNotation : NotationInOneMove -> SidebarMoveData
condenseMoveNotation move =
    { moveNumber = move.moveNumber
    , color = move.color
    , actions =
        case move.actions of
            [] ->
                []

            [ ( i, a ) ] ->
                [ { actionIndex = i, actions = [ a ] } ]

            ( _, a ) :: ( i, b ) :: tail ->
                { actionIndex = i, actions = [ a, b ] } :: condenseTail tail
    }


condenseTail : List ( Int, NotationAtom ) -> List ConsensedActionKey
condenseTail tuples =
    List.map (\( i, a ) -> { actionIndex = i, actions = [ a ] }) tuples


{-| This is one action (or two) referenced by their action index in the game
history together with the NotationAtom(s) that shoud be shown together.
-}
type alias ConsensedActionKey =
    { actionIndex : Int
    , actions : List NotationAtom
    }


{-| Tracks the list of actions broken down into moves.
-}
type alias ActionsInOneMove =
    { moveNumber : Int
    , color : Sako.Color
    , actions : List ( Int, Sako.Action )
    }


{-| Tracks the list of actions broken down into moves.
-}
type alias NotationInOneMove =
    { moveNumber : Int
    , color : Sako.Color
    , actions : List ( Int, NotationAtom )
    }


{-| Cuts the actions into moves and attaches some metadata while doing it.
Each move starts with a Lift action so this is how we recognize them.
-}
breakHistoryIntoMoves : List ( Sako.Action, a ) -> List ActionsInOneMove
breakHistoryIntoMoves history =
    history
        |> List.indexedMap (\i ( action, _ ) -> ( i + 1, action ))
        |> List.breakAt (\( _, action ) -> Sako.isLiftAction action)
        |> List.indexedMap
            (\i actions ->
                { moveNumber = i // 2 + 1
                , color =
                    if modBy 2 i == 0 then
                        Sako.White

                    else
                        Sako.Black
                , actions = actions
                }
            )


translateActionsToNotation : Sako.Position -> List ActionsInOneMove -> List NotationInOneMove
translateActionsToNotation position moves =
    List.mapAccuml applyOneMove position moves |> Tuple.second


{-| Takes a position and applies one move. While doing this, the notation for
this move is derived and returned.

You can just think of this as a state monad with Sako.Position as state.

-}
applyOneMove : Sako.Position -> ActionsInOneMove -> ( Sako.Position, NotationInOneMove )
applyOneMove position move =
    let
        ( nextPosition, actions ) =
            List.mapAccuml (applyOneAction move.color) position move.actions
    in
    ( nextPosition
    , { moveNumber = move.moveNumber
      , color = move.color
      , actions = actions
      }
    )


applyOneAction : Sako.Color -> Sako.Position -> ( Int, Sako.Action ) -> ( Sako.Position, ( Int, NotationAtom ) )
applyOneAction color position ( i, action ) =
    let
        nextPosition =
            Sako.doAction action position |> Maybe.withDefault position
    in
    case action of
        Sako.Lift tile ->
            case Sako.getPiecesAt position tile |> orderFor color of
                [ piece ] ->
                    ( nextPosition
                    , ( i, StartMoveSingle piece.pieceType tile )
                    )

                [ pieceA, pieceB ] ->
                    ( nextPosition
                    , ( i, StartMoveUnion pieceA.pieceType pieceB.pieceType tile )
                    )

                [] ->
                    ( nextPosition, ( i, NotationError "applyOneAction: Lift: no piece" ) )

                _ ->
                    ( nextPosition, ( i, NotationError "applyOneAction: Lift: too many pieces" ) )

        Sako.Place tile ->
            ( nextPosition
            , ( i
              , case Sako.getPiecesAt position tile of
                    [] ->
                        EndMoveCalm tile

                    [ piece ] ->
                        EndMoveFormUnion piece.pieceType tile

                    [ pieceA, pieceB ] ->
                        if pieceA.color == color then
                            ContinueChain pieceA.pieceType tile

                        else
                            ContinueChain pieceB.pieceType tile

                    _ ->
                        NotationError "applyOneAction: Place: too many pieces"
              )
            )

        Sako.Promote type_ ->
            ( nextPosition
            , ( i, Promote type_ )
            )


orderFor : Sako.Color -> List Sako.Piece -> List Sako.Piece
orderFor color entries =
    let
        whitePieces =
            List.filter (Sako.isColor Sako.White) entries

        blackPieces =
            List.filter (Sako.isColor Sako.Black) entries
    in
    case color of
        Sako.White ->
            whitePieces ++ blackPieces

        Sako.Black ->
            blackPieces ++ whitePieces


{-| Takes all the Notation Atoms, renders them separately and then concatenates them.
-}
writeOut : List NotationAtom -> String
writeOut steps =
    List.map renderAtom steps
        |> String.concat


{-| Turn a list of Atoms into a String.
-}
renderAtom : NotationAtom -> String
renderAtom atom =
    case atom of
        StartMoveSingle type_ tile ->
            letter type_ ++ Sako.tileToIdentifier tile

        StartMoveUnion typeA typeB tile ->
            letter typeA ++ letter typeB ++ Sako.tileToIdentifier tile

        ContinueChain type_ tile ->
            ">" ++ letter type_ ++ Sako.tileToIdentifier tile

        EndMoveCalm tile ->
            ">" ++ Sako.tileToIdentifier tile

        EndMoveFormUnion type_ tile ->
            "x" ++ letter type_ ++ Sako.tileToIdentifier tile

        NotationError _ ->
            "!"

        Promote type_ ->
            "=" ++ letter type_


letter : Sako.Type -> String
letter type_ =
    case type_ of
        Sako.Pawn ->
            ""

        Sako.Knight ->
            "N"

        Sako.Bishop ->
            "B"

        Sako.Rook ->
            "R"

        Sako.Queen ->
            "Q"

        Sako.King ->
            "K"
