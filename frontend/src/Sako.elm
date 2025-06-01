module Sako exposing
    ( Action(..)
    , Color(..)
    , Piece
    , Position
    , SetupOptions
    , Type(..)
    , VictoryState(..)
    , actionTile
    , decodeAction
    , decodeColor
    , decodeFlatTile
    , decodeSetupOptions
    , decodeVictoryState
    , doAction
    , doActionsList
    , dummySetupOptions
    , emptyPosition
    , encodeAction
    , encodeColor
    , encodeSetupOptions
    , enumeratePieceIdentity
    , exportExchangeNotation
    , getPiecesAt
    , importExchangeNotation
    , initialPosition
    , isAt
    , isChaining
    , isColor
    , isLift
    , isPromoting
    , liftedAtTile
    , toStringType
    )

{-| Everything you need to express the Position of a Paco Ŝako board.

It also contains some logic abouth what kind of moves / actions are possible
and how they affect the game position. Note that the full rules of the game
are only implemented in Rust at this point, so we need to call into Rust
when we need this info.

This module also contains methods for exporting and importing a human readable
plain text exchange notation.

The scope of this module is limited to abstract representations of the board.
No rendering is done in here.

-}

import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import List.Extra as List
import Parser exposing ((|.), (|=), Parser)
import Tile exposing (Tile(..))


{-| Enum that lists all possible types of pieces that can be in play.
-}
type Type
    = Pawn
    | Rook
    | Knight
    | Bishop
    | Queen
    | King


fromStringType : String -> Decoder Type
fromStringType string =
    case string of
        "Bishop" ->
            Decode.succeed Bishop

        "King" ->
            Decode.succeed King

        "Knight" ->
            Decode.succeed Knight

        "Pawn" ->
            Decode.succeed Pawn

        "Queen" ->
            Decode.succeed Queen

        "Rook" ->
            Decode.succeed Rook

        _ ->
            Decode.fail ("Not valid pattern for decoder to Type. Pattern: " ++ string)


toStringType : Type -> String
toStringType pieceType =
    case pieceType of
        Pawn ->
            "Pawn"

        Rook ->
            "Rook"

        Knight ->
            "Knight"

        Bishop ->
            "Bishop"

        Queen ->
            "Queen"

        King ->
            "King"


decodeType : Decoder Type
decodeType =
    Decode.string |> Decode.andThen fromStringType


encodeType : Type -> Value
encodeType =
    toStringType >> Encode.string


{-| The abstract color of a Paco Ŝako piece. The white player always goes first
and the black player always goes second. This has no bearing on the color with
which the pieces are rendered on the board.

This type is also used to represent the parties in a game.

-}
type Color
    = White
    | Black


fromStringColor : String -> Decoder Color
fromStringColor string =
    case string of
        "Black" ->
            Decode.succeed Black

        "White" ->
            Decode.succeed White

        _ ->
            Decode.fail ("Not valid pattern for decoder to Color. Pattern: " ++ string)


decodeColor : Decoder Color
decodeColor =
    Decode.string |> Decode.andThen fromStringColor


encodeColor : Color -> Value
encodeColor color =
    case color of
        White ->
            Encode.string "White"

        Black ->
            Encode.string "Black"


{-| Represents a Paco Ŝako playing piece with type, color and position.

Only positions on the board are allowed, lifted positions are not expressed
with this type.

-}
type alias Piece =
    { pieceType : Type
    , color : Color
    , position : Tile
    , identity : String
    }


isAt : Tile -> Piece -> Bool
isAt tile piece =
    piece.position == tile


isColor : Color -> Piece -> Bool
isColor color piece =
    piece.color == color


pacoPiece : Color -> Type -> Tile -> Piece
pacoPiece color pieceType position =
    { pieceType = pieceType, color = color, position = position, identity = "" }


defaultInitialPosition : List Piece
defaultInitialPosition =
    [ pacoPiece White Rook (Tile 0 0)
    , pacoPiece White Knight (Tile 1 0)
    , pacoPiece White Bishop (Tile 2 0)
    , pacoPiece White Queen (Tile 3 0)
    , pacoPiece White King (Tile 4 0)
    , pacoPiece White Bishop (Tile 5 0)
    , pacoPiece White Knight (Tile 6 0)
    , pacoPiece White Rook (Tile 7 0)
    , pacoPiece White Pawn (Tile 0 1)
    , pacoPiece White Pawn (Tile 1 1)
    , pacoPiece White Pawn (Tile 2 1)
    , pacoPiece White Pawn (Tile 3 1)
    , pacoPiece White Pawn (Tile 4 1)
    , pacoPiece White Pawn (Tile 5 1)
    , pacoPiece White Pawn (Tile 6 1)
    , pacoPiece White Pawn (Tile 7 1)
    , pacoPiece Black Pawn (Tile 0 6)
    , pacoPiece Black Pawn (Tile 1 6)
    , pacoPiece Black Pawn (Tile 2 6)
    , pacoPiece Black Pawn (Tile 3 6)
    , pacoPiece Black Pawn (Tile 4 6)
    , pacoPiece Black Pawn (Tile 5 6)
    , pacoPiece Black Pawn (Tile 6 6)
    , pacoPiece Black Pawn (Tile 7 6)
    , pacoPiece Black Rook (Tile 0 7)
    , pacoPiece Black Knight (Tile 1 7)
    , pacoPiece Black Bishop (Tile 2 7)
    , pacoPiece Black Queen (Tile 3 7)
    , pacoPiece Black King (Tile 4 7)
    , pacoPiece Black Bishop (Tile 5 7)
    , pacoPiece Black Knight (Tile 6 7)
    , pacoPiece Black Rook (Tile 7 7)
    ]
        |> enumeratePieceIdentity 0


{-| In order to get animations right, we need to render the lists with Svg.Keyed.
We assign a unique ID to each piece that will allow us to track the identity of
pieces across different board states.
-}
enumeratePieceIdentity : Int -> List Piece -> List Piece
enumeratePieceIdentity starting pieces =
    List.indexedMap
        (\i p -> { p | identity = "enumerate" ++ String.fromInt (starting + i) })
        pieces


{-| An atomic action that you can take on a Paco Ŝako board.
-}
type Action
    = Lift Tile
    | Place Tile
    | Promote Type


isLift : Action -> Bool
isLift action =
    case action of
        Lift _ ->
            True

        _ ->
            False


decodeAction : Decoder Action
decodeAction =
    Decode.oneOf
        [ Decode.map Lift (Decode.at [ "Lift" ] decodeFlatTile)
        , Decode.map Place (Decode.at [ "Place" ] decodeFlatTile)
        , Decode.map Promote (Decode.at [ "Promote" ] decodeType)
        ]


encodeAction : Action -> Value
encodeAction action =
    case action of
        Lift tile ->
            Encode.object [ ( "Lift", Encode.int (Tile.toFlat tile) ) ]

        Place tile ->
            Encode.object [ ( "Place", Encode.int (Tile.toFlat tile) ) ]

        Promote pacoType ->
            Encode.object [ ( "Promote", encodeType pacoType ) ]


decodeFlatTile : Decoder Tile
decodeFlatTile =
    Decode.map Tile.fromFlat Decode.int


actionTile : Action -> Maybe Tile
actionTile action =
    case action of
        Lift tile ->
            Just tile

        Place tile ->
            Just tile

        _ ->
            Nothing


type VictoryState
    = Running
    | PacoVictory Color
    | TimeoutVictory Color
    | NoProgressDraw
    | RepetitionDraw


decodeVictoryState : Decoder VictoryState
decodeVictoryState =
    Decode.oneOf
        [ Decode.string
            |> Decode.andThen
                (\str ->
                    if str == "Running" then
                        Decode.succeed Running

                    else
                        Decode.fail "Expected constant string 'Running'."
                )
        , Decode.map TimeoutVictory
            (Decode.field "TimeoutVictory" decodeColor)
        , Decode.map PacoVictory
            (Decode.field "PacoVictory" decodeColor)
        , Decode.string
            |> Decode.andThen
                (\str ->
                    if str == "NoProgressDraw" then
                        Decode.succeed NoProgressDraw

                    else if str == "RepetitionDraw" then
                        Decode.succeed RepetitionDraw

                    else
                        Decode.fail "Expected constant string 'NoProgressDraw'."
                )
        ]


{-| If there is currently a lifted piece (or two), then this returns the tile.
-}
liftedAtTile : Position -> Maybe Tile
liftedAtTile position =
    position.liftedPieces
        |> List.head
        |> Maybe.map .position


{-| Check if there currently is an active chain.
-}
isChaining : Position -> Bool
isChaining position =
    case position.liftedPieces of
        [ lifted ] ->
            List.any (isAt lifted.position) position.pieces

        _ ->
            False


{-| Check if there currently is a promotion happening.
-}
isPromoting : Position -> Bool
isPromoting position =
    isWhitePromoting position || isBlackPromoting position


isWhitePromoting : Position -> Bool
isWhitePromoting position =
    List.any (\p -> p.pieceType == Pawn && p.color == White && Tile.getY p.position == 7) position.pieces


isBlackPromoting : Position -> Bool
isBlackPromoting position =
    List.any (\p -> p.pieceType == Pawn && p.color == Black && Tile.getY p.position == 0) position.pieces


{-| Validates and executes an action. This does not validate that the position
is actually legal and executing an action on an invalid position is undefined
behaviour. However if you start with a valid position and only modify it using
this doAction method you can be sure that the position is still valid.
-}
doAction : Action -> Position -> Maybe Position
doAction action position =
    case action of
        Lift tile ->
            doLiftAction tile position

        Place tile ->
            doPlaceAction tile position

        Promote pieceType ->
            doPromoteAction pieceType position


{-| Iterate `Sako.doAction` with the actions provided on the board state.
-}
doActionsList : List Action -> Position -> Maybe Position
doActionsList actions board =
    case actions of
        [] ->
            Just board

        a :: actionTail ->
            doAction a board
                |> Maybe.andThen (\b -> doActionsList actionTail b)


{-| Check that there is nothing lifted right now and then lift the piece at the
given position. Also checks that you own it or it is a pair.
-}
doLiftAction : Tile -> Position -> Maybe Position
doLiftAction tile position =
    let
        piecesToLift =
            getPiecesAt position tile
    in
    if List.isEmpty position.liftedPieces then
        Just
            { position
                | pieces = position.pieces |> List.filter (not << isAt tile)
                , liftedPieces = piecesToLift
            }

    else
        Nothing


{-| Returns all pieces which are currently resting on the given tile.
This will not return lifted pieces.
-}
getPiecesAt : Position -> Tile -> List Piece
getPiecesAt position tile =
    position.pieces |> List.filter (isAt tile)


{-| Compares currently lifted pieces with the targed and then either
chains or places down the pieces.
-}
doPlaceAction : Tile -> Position -> Maybe Position
doPlaceAction tile position =
    case position.liftedPieces of
        [] ->
            Nothing

        [ piece ] ->
            doPlaceSingleAction piece tile position

        _ ->
            doPlacePairAction tile position


doPlacePairAction : Tile -> Position -> Maybe Position
doPlacePairAction tile position =
    let
        targetPieces =
            List.filter (isAt tile) position.pieces
    in
    case targetPieces of
        [] ->
            Just (unsafePlaceAt tile position)

        _ ->
            Nothing


{-| This function can be called when a place action is executed while exactly
one piece is lifted.
-}
doPlaceSingleAction : Piece -> Tile -> Position -> Maybe Position
doPlaceSingleAction piece tile position =
    if isEnPassantCapture piece tile position then
        doEnPassantPreparation tile position
            |> doPlaceSingleActionNoSpecialMoves piece tile

    else if isCastlingMove piece tile position then
        Just (doCastlingMove piece tile position)

    else
        doPlaceSingleActionNoSpecialMoves piece tile position


{-| An en passant capture can be identified by checking if a paws moves
diagonally to an empty position. This happens exactly when uniting/chaining
en passant. After moving the real target back, a normal union/chain happens.
-}
isEnPassantCapture : Piece -> Tile -> Position -> Bool
isEnPassantCapture piece tile position =
    (piece.pieceType == Pawn)
        && (Tile.getX piece.position /= Tile.getX tile)
        && List.all (not << isAt tile) position.pieces


{-| Moves everything in front of the given tile back to this tile, in
preparation for an enPassant union or chain.
-}
doEnPassantPreparation : Tile -> Position -> Position
doEnPassantPreparation (Tile x y) position =
    if y == 2 then
        unsafeDirectMove (Tile x 3) (Tile x 2) position

    else if y == 5 then
        unsafeDirectMove (Tile x 4) (Tile x 5) position

    else
        position


{-| Identifies a castling move. Since we introduced Fischer random chess,
there are two conditions to check.

  - We must be placing the king and either of
      - The king must move more than one square in the x direction.
      - The "place target" is occupied by a piece of the same color.

Having either of these conditions is a neccessary, but not sufficient for a
castling move to be valid. But we leave move validation to the rust code which
can check sufficient conditions.

-}
isCastlingMove : Piece -> Tile -> Position -> Bool
isCastlingMove piece tile position =
    piece.pieceType
        == King
        && (abs (Tile.getX tile - Tile.getX piece.position)
                > 1
                || List.any (\p -> isAt tile p && isColor piece.color p) position.pieces
           )


{-| Places the king and moves the Rook (maybe with partner). This function must
only be called if you have verified that castling really takes place.

To work with Fischer random chess, we need to figure out the actual king and
rook movement.

-}
doCastlingMove : Piece -> Tile -> Position -> Position
doCastlingMove king tile position =
    let
        (Tile tx ty) =
            tile

        (Tile kx _) =
            king.position

        -- Are we king side or queen side?
        isQueenSide =
            tx < kx

        ( new_kx, new_rx ) =
            if isQueenSide then
                ( 2, 3 )

            else
                ( 6, 5 )

        -- Try to grap the rook that was clicked (Fischer) and if there is none
        -- fall back to standard rook positioning.
        rx =
            List.filter (\p -> isAt tile p && isColor king.color p) position.pieces
                |> List.head
                |> Maybe.map (\rook -> Tile.getX rook.position)
                |> Maybe.withDefault
                    (if isQueenSide then
                        0

                     else
                        7
                    )
    in
    -- The king is currently in hand and can not conflict with any piece on the
    -- board for now. So we first move the rook. Then we place the king.
    -- This ordering is important for Fischer random.
    position
        |> unsafeDirectMove (Tile rx ty) (Tile new_rx ty)
        |> unsafePlaceAt (Tile new_kx ty)


{-| This function can be called when a single piece is placed and it has already
been verified that neither a castling nor a en passant capture is happening.
-}
doPlaceSingleActionNoSpecialMoves : Piece -> Tile -> Position -> Maybe Position
doPlaceSingleActionNoSpecialMoves piece tile position =
    let
        targetPieces =
            List.filter (isAt tile) position.pieces
    in
    case targetPieces of
        [] ->
            Just (unsafePlaceAt tile position)

        [ other ] ->
            if other.color /= piece.color then
                Just (unsafePlaceAt tile position)

            else
                Nothing

        _ ->
            Just (unsafePlaceChainAction piece tile position)


{-| Calling this function is only valid when there are two pieces at the
provided tile location. (This implies this function must never be exposed
directly outside the module.)
-}
unsafePlaceChainAction : Piece -> Tile -> Position -> Position
unsafePlaceChainAction piece tile position =
    let
        isChainParter p =
            p.color == piece.color && p.position == tile

        targetPieceOfSameColor =
            List.filter isChainParter position.pieces

        remainingRestingPieces =
            List.filter (not << isChainParter) position.pieces
    in
    { position
        | liftedPieces = targetPieceOfSameColor
        , pieces = { piece | position = tile } :: remainingRestingPieces
    }


{-| Places all pieces in hand to the `tile` without any checks.

Calling this function is only valid when the hand and the target position
don't have two pieces of the same color between them.

-}
unsafePlaceAt : Tile -> Position -> Position
unsafePlaceAt tile position =
    let
        movedHand =
            position.liftedPieces |> List.map (\p -> { p | position = tile })
    in
    { position
        | pieces = movedHand ++ position.pieces
        , liftedPieces = []
    }


{-| Moves all pieces on the `from` tile to the `to` tile without any checks.
-}
unsafeDirectMove : Tile -> Tile -> Position -> Position
unsafeDirectMove from to position =
    { position
        | pieces =
            position.pieces
                |> List.map (unsafeDirectMovePiece from to)
    }


{-| Moves a single piece on the `from` tile to the `to` tile if it is there.
-}
unsafeDirectMovePiece : Tile -> Tile -> Piece -> Piece
unsafeDirectMovePiece from to piece =
    if piece.position == from then
        { piece | position = to }

    else
        piece


{-| Check that there is exactly one pawn that is set to promote and then change
its type.
-}
doPromoteAction : Type -> Position -> Maybe Position
doPromoteAction pieceType position =
    let
        whitePawnFilter p =
            Tile.getY p.position == 7 && p.color == White

        blackPawnFilter p =
            Tile.getY p.position == 0 && p.color == Black

        pawnFilter p =
            p.pieceType == Pawn && (whitePawnFilter p || blackPawnFilter p)

        ownPawnsOnHomeRow =
            position.pieces
                |> List.filter pawnFilter
    in
    if List.length ownPawnsOnHomeRow == 1 then
        Just { position | pieces = position.pieces |> List.updateIf pawnFilter (\p -> { p | pieceType = pieceType }) }

    else
        Nothing



--------------------------------------------------------------------------------
-- The state of a game is a Position -------------------------------------------
--------------------------------------------------------------------------------


type alias Position =
    { pieces : List Piece
    , liftedPieces : List Piece

    -- the currentPlayer flag is currently defective and not properly updated.
    , currentPlayer : Color
    }


initialPosition : Position
initialPosition =
    { pieces = defaultInitialPosition
    , liftedPieces = []
    , currentPlayer = White
    }


emptyPosition : Position
emptyPosition =
    { pieces = []
    , liftedPieces = []
    , currentPlayer = White
    }


positionFromPieces : List Piece -> Position
positionFromPieces pieces =
    { emptyPosition | pieces = pieces }


{-| The state also depends on its initial setup.
-}
type alias SetupOptions =
    { safeMode : Bool
    , drawAfterNRepetitions : Int
    , startingFen : String
    }


dummySetupOptions : SetupOptions
dummySetupOptions =
    { safeMode = True
    , drawAfterNRepetitions = 3
    , startingFen = default_starting_fen
    }


default_starting_fen : String
default_starting_fen =
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w 0 AHah - -"


encodeSetupOptions : SetupOptions -> Value
encodeSetupOptions options =
    Encode.object
        [ ( "safe_mode", Encode.bool options.safeMode )
        , ( "draw_after_n_repetitions", Encode.int options.drawAfterNRepetitions )
        , ( "starting_fen", Encode.string options.startingFen )
        ]


decodeSetupOptions : Decoder SetupOptions
decodeSetupOptions =
    Decode.map3 SetupOptions
        (Decode.field "safe_mode" Decode.bool)
        (Decode.field "draw_after_n_repetitions" Decode.int)
        (Decode.field "starting_fen"
            (Decode.nullable Decode.string
                |> Decode.map (Maybe.withDefault default_starting_fen)
            )
        )



--------------------------------------------------------------------------------
-- Exporting to exchange notation and parsing it -------------------------------
--------------------------------------------------------------------------------


{-| Converts a Paco Ŝako position into a human readable version that can be
copied and stored in a text file.
-}
abstractExchangeNotation : String -> List Piece -> String
abstractExchangeNotation lineSeparator pieces =
    let
        dictRepresentation =
            pacoPositionAsGrid pieces

        tileEntry : Int -> String
        tileEntry i =
            Dict.get i dictRepresentation
                |> Maybe.withDefault EmptyTile
                |> tileStateAsString

        markdownRow : List Int -> String
        markdownRow indexRow =
            String.join " " (List.map tileEntry indexRow)

        indices =
            [ [ 56, 57, 58, 59, 60, 61, 62, 63 ]
            , [ 48, 49, 50, 51, 52, 53, 54, 55 ]
            , [ 40, 41, 42, 43, 44, 45, 46, 47 ]
            , [ 32, 33, 34, 35, 36, 37, 38, 39 ]
            , [ 24, 25, 26, 27, 28, 29, 30, 31 ]
            , [ 16, 17, 18, 19, 20, 21, 22, 23 ]
            , [ 8, 9, 10, 11, 12, 13, 14, 15 ]
            , [ 0, 1, 2, 3, 4, 5, 6, 7 ]
            ]
    in
    indices
        |> List.map markdownRow
        |> String.join lineSeparator


{-| Given a list of Paco Ŝako Pieces (type, color, position), this function
exports the position into the human readable exchange notation for Paco Ŝako.
Here is an example:

    .. .. .. .B .. .. .. ..
    .B R. .. .. .Q .. .. P.
    .. .P .P .K .. NP P. ..
    PR .R PP .. .. .. .. ..
    K. .P P. .. NN .. .. ..
    P. .P .. P. .. .. BP R.
    P. .. .P .. .. .. BN Q.
    .. .. .. .. .. .. .. ..

-}
exportExchangeNotation : Position -> String
exportExchangeNotation position =
    abstractExchangeNotation "\n" position.pieces


type TileState
    = EmptyTile
    | WhiteTile Type
    | BlackTile Type
    | PairTile Type Type


{-| Converts a PacoPosition into a map from 1d tile indices to tile states
-}
pacoPositionAsGrid : List Piece -> Dict Int TileState
pacoPositionAsGrid pieces =
    let
        colorTiles filterColor =
            pieces
                |> List.filter (\piece -> piece.color == filterColor)
                |> List.map (\piece -> ( Tile.toFlat piece.position, piece.pieceType ))
                |> Dict.fromList
    in
    Dict.merge
        (\i w dict -> Dict.insert i (WhiteTile w) dict)
        (\i w b dict -> Dict.insert i (PairTile w b) dict)
        (\i b dict -> Dict.insert i (BlackTile b) dict)
        (colorTiles White)
        (colorTiles Black)
        Dict.empty


gridAsPacoPosition : List (List TileState) -> List Piece
gridAsPacoPosition tiles =
    indexedMapNest2 tileAsPacoPiece tiles
        |> List.concat
        |> List.concat
        |> enumeratePieceIdentity 0


tileAsPacoPiece : Int -> Int -> TileState -> List Piece
tileAsPacoPiece row col tile =
    let
        position =
            Tile col (7 - row)
    in
    case tile of
        EmptyTile ->
            []

        WhiteTile w ->
            [ pacoPiece White w position ]

        BlackTile b ->
            [ pacoPiece Black b position ]

        PairTile w b ->
            [ pacoPiece White w position
            , pacoPiece Black b position
            ]


indexedMapNest2 : (Int -> Int -> a -> b) -> List (List a) -> List (List b)
indexedMapNest2 f ls =
    List.indexedMap
        (\i xs ->
            List.indexedMap (\j x -> f i j x) xs
        )
        ls


tileStateAsString : TileState -> String
tileStateAsString tileState =
    case tileState of
        EmptyTile ->
            ".."

        WhiteTile w ->
            markdownTypeChar w ++ "."

        BlackTile b ->
            "." ++ markdownTypeChar b

        PairTile w b ->
            markdownTypeChar w ++ markdownTypeChar b


markdownTypeChar : Type -> String
markdownTypeChar pieceType =
    case pieceType of
        Pawn ->
            "P"

        Rook ->
            "R"

        Knight ->
            "N"

        Bishop ->
            "B"

        Queen ->
            "Q"

        King ->
            "K"


{-| Parser that converts a single letter into the corresponding sako type.
-}
parseTypeChar : Parser (Maybe Type)
parseTypeChar =
    Parser.oneOf
        [ Parser.succeed (Just Pawn) |. Parser.symbol "P"
        , Parser.succeed (Just Rook) |. Parser.symbol "R"
        , Parser.succeed (Just Knight) |. Parser.symbol "N"
        , Parser.succeed (Just Bishop) |. Parser.symbol "B"
        , Parser.succeed (Just Queen) |. Parser.symbol "Q"
        , Parser.succeed (Just King) |. Parser.symbol "K"
        , Parser.succeed Nothing |. Parser.symbol "."
        ]


{-| Parser that converts a pair like ".P", "BQ", ".." into a TileState.
-}
parseTile : Parser TileState
parseTile =
    Parser.succeed tileFromMaybe
        |= parseTypeChar
        |= parseTypeChar


tileFromMaybe : Maybe Type -> Maybe Type -> TileState
tileFromMaybe white black =
    case ( white, black ) of
        ( Nothing, Nothing ) ->
            EmptyTile

        ( Just w, Nothing ) ->
            WhiteTile w

        ( Nothing, Just b ) ->
            BlackTile b

        ( Just w, Just b ) ->
            PairTile w b


parseRow : Parser (List TileState)
parseRow =
    sepBy parseTile (Parser.symbol " ")
        |> Parser.andThen parseLengthEightCheck


parseGrid : Parser (List (List TileState))
parseGrid =
    sepBy parseRow linebreak
        |> Parser.andThen parseLengthEightCheck


parsePosition : Parser (List Piece)
parsePosition =
    parseGrid
        |> Parser.map gridAsPacoPosition


{-| Given a position in human readable exchange notation for Paco Ŝako,
this function parses it and returns a list of Pieces (type, color, position).
Here is an example of the notation:

    .. .. .. .B .. .. .. ..
    .B R. .. .. .Q .. .. P.
    .. .P .P .K .. NP P. ..
    PR .R PP .. .. .. .. ..
    K. .P P. .. NN .. .. ..
    P. .P .. P. .. .. BP R.
    P. .. .P .. .. .. BN Q.
    .. .. .. .. .. .. .. ..

-}
importExchangeNotation : String -> Result String Position
importExchangeNotation input =
    Parser.run parsePosition input
        |> Result.mapError (\_ -> "There is an error in the position notation :-(")
        |> Result.map positionFromPieces


linebreak : Parser ()
linebreak =
    Parser.chompWhile (\c -> c == '\n' || c == '\u{000D}')


{-| Parse a string with many tiles and return them as a list. When we encounter
".B " with a trailing space, then we know that more tiles must follow.
If there is no trailing space, we return.
-}
parseLengthEightCheck : List a -> Parser (List a)
parseLengthEightCheck list =
    if List.length list == 8 then
        Parser.succeed list

    else
        Parser.problem "There must be 8 columns in each row."


{-| Using `sepBy content separator` you can parse zero or more occurrences of
the `content`, separated by `separator`.

Returns a list of values returned by `content`.

-}
sepBy : Parser a -> Parser () -> Parser (List a)
sepBy content separator =
    let
        helper ls =
            Parser.oneOf
                [ Parser.succeed (\tile -> Parser.Loop (tile :: ls))
                    |= content
                    |. Parser.oneOf [ separator, Parser.succeed () ]
                , Parser.succeed (Parser.Done ls)
                ]
    in
    Parser.loop [] helper
        |> Parser.map List.reverse
