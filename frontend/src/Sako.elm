module Sako exposing
    ( Action
    , Color(..)
    , Piece
    , Position
    , Tile(..)
    , Type(..)
    , decodePosition
    , emptyPosition
    , encodePosition
    , exportExchangeNotation
    , importExchangeNotation
    , importExchangeNotationList
    , initialPosition
    , isAt
    , isColor
    )

{-| Everything you need to express the Position of a Paco Ŝako board.

This module also contains methods for exporting and importing a human readable
plain text exchange notation.

The scope of this module is limited to abstract representations of the board.
No rendering is done in here.

-}

import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import Parser exposing ((|.), (|=), Parser)


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


toStringColor : Color -> String
toStringColor color =
    case color of
        White ->
            "White"

        Black ->
            "Black"


decodeColor : Decoder Color
decodeColor =
    Decode.string |> Decode.andThen fromStringColor


encodeColor : Color -> Value
encodeColor =
    toStringColor >> Encode.string


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


{-| Deserializes a Piece.
-}
decodePacoPiece : Decoder Piece
decodePacoPiece =
    Decode.map4 Piece
        (Decode.field "pieceType" decodeType)
        (Decode.field "color" decodeColor)
        (Decode.field "position" decodeTile)
        (Decode.field "identity" Decode.string)


{-| Serializes a Piece.

This also stores the identity of the piece which is important for tracking
pieces across multiple board states. If we did not store this information with
the pieces, animations would not work.

-}
encodePiece : Piece -> Value
encodePiece record =
    Encode.object
        [ ( "pieceType", encodeType <| record.pieceType )
        , ( "color", encodeColor <| record.color )
        , ( "position", encodeTile <| record.position )
        , ( "identity", Encode.string record.identity )
        ]


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
        |> enumeratePieceIdentity


{-| In order to get animations right, we need to render the lists with Svg.Keyed.
We assign a unique ID to each piece that will allow us to track the identity of
pieces across different board states.
-}
enumeratePieceIdentity : List Piece -> List Piece
enumeratePieceIdentity pieces =
    List.indexedMap
        (\i p -> { p | identity = "enumerate" ++ String.fromInt i })
        pieces


{-| The atomic actions you can execute on a Paco Ŝako board.
-}
type Action
    = LiftAction Tile
    | PlaceAction Tile
    | PromoteAction Type



--------------------------------------------------------------------------------
-- Tiles -----------------------------------------------------------------------
--------------------------------------------------------------------------------


{-| Represents the position of a single abstract board tile.
`Tile x y` stores two integers with legal values between 0 and 7 (inclusive).
Use `tileX` and `tileY` to extract individual coordinates.
-}
type Tile
    = Tile Int Int


{-| 1d coordinate for a tile. This is just x + 8 \* y
-}
tileFlat : Tile -> Int
tileFlat (Tile x y) =
    x + 8 * y


encodeTile : Tile -> Value
encodeTile (Tile x y) =
    Encode.object [ ( "x", Encode.int x ), ( "y", Encode.int y ) ]


decodeTile : Decoder Tile
decodeTile =
    Decode.map2 Tile
        (Decode.field "x" Decode.int)
        (Decode.field "y" Decode.int)



--------------------------------------------------------------------------------
-- The state of a game is a Position -------------------------------------------
--------------------------------------------------------------------------------


type alias Position =
    { pieces : List Piece
    , liftedPiece : Maybe Piece
    }


initialPosition : Position
initialPosition =
    { pieces = defaultInitialPosition
    , liftedPiece = Nothing
    }


emptyPosition : Position
emptyPosition =
    { pieces = []
    , liftedPiece = Nothing
    }


positionFromPieces : List Piece -> Position
positionFromPieces pieces =
    { emptyPosition | pieces = pieces }


decodePosition : Decoder Position
decodePosition =
    Decode.map2 Position
        (Decode.field "pieces" (Decode.list decodePacoPiece))
        (Decode.field "liftedPiece" (Decode.nullable decodePacoPiece))


encodePosition : Position -> Value
encodePosition record =
    Encode.object
        [ ( "pieces", Encode.list encodePiece <| record.pieces )
        , ( "liftedPiece", Maybe.withDefault Encode.null <| Maybe.map encodePiece <| record.liftedPiece )
        ]



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
                |> List.map (\piece -> ( tileFlat piece.position, piece.pieceType ))
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
        |> enumeratePieceIdentity


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


{-| A library is a list of PacoPositions separated by a newline.
Deprecated: In the future the examples won't come from a file, instead it will
be read from the server in a json where each position data has a separate
field anyway. Then this function won't be needed anymore.
-}
parseLibrary : Parser (List (List Piece))
parseLibrary =
    sepBy parsePosition (Parser.symbol "-" |. linebreak)


{-| Given a file that contains many Paco Ŝako in human readable exchange notation
separated by a '-' character, this function parses all positions.
-}
importExchangeNotationList : String -> Result String (List Position)
importExchangeNotationList input =
    Parser.run parseLibrary input
        |> Result.mapError (\_ -> "There is an error in the position notation :-(")
        |> Result.map (List.map positionFromPieces)


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
