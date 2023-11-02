use lazy_static::lazy_static;

use std::collections::HashMap;

use crate::{
    parser::Square, substrate::Substrate, BoardPosition, Castling, DenseBoard, PacoError,
    PlayerColor,
};
use lazy_regex::regex_captures;

/// This module implements an extension of X-Fen that can represent settled Paco
/// Ŝako boards (i.e. boards without an active chain) together with most state.
///
/// It should be mostly compatible with <https://vchess.club/#/variants/Pacosako>
/// where I got the union notation. There are somewhat different pawn rules on the
/// vchess.club version, which explains the difference.
///
/// Fen looks like this:
///
/// > bqnrkb1r/pppppppp/5n2/8/3P4/8/PPP1PPPP/NRBKRBNQ w 2 bedh - -
/// > <pieces on board> <controlling player> <move count> <castling> <en passant> <union move>
///
/// The extension by vchess are:
///
///   - A bit string with 16 entries, one for each pawn column and color if the player
///     already moved their pawn in this column. (Only allowed once on vchess)
///   - The last pair move (if any), as undoing the same move directly is forbidden.
///
/// For compatibility we also include the <union move> as our fen could not be read
/// by the vchess page otherwise - even though we don't implement the ko rule.

// This needs its own method or rustfmt gets unhappy.
fn regex(input: &str) -> Option<(&str, &str, &str, &str, &str, &str)> {
    regex_captures!(
        "((?:(?:[a-zA-Z1-8]+)/?){8}) ([wb]) ([0-9]+) ([A-H]{0,2}[a-h]{0,2}|-) ([a-h][1-8]|-) -",
        input
    )
}

lazy_static! {
    static ref CHAR_TO_SQUARE: HashMap<char, Square> = {
        let mut map = lowercase_char_to_square();

        // Now we put everything in again, but for uppercase keys and flipped values.
        map.clone().iter().for_each(|(k, v)| {
            map.insert(k.to_ascii_uppercase(), v.flip());
        });

        map

    };

    static ref SQUARE_TO_CHAR: HashMap<Square, char> = {
        let reverse = lowercase_char_to_square();
        let mut map: HashMap<Square, char> = HashMap::new();

        reverse.iter().for_each(|(c, square)| {
            map.insert(square.clone(), *c);
        });
        // By going over lower case characters first, we make sure those get preferred.
        reverse.iter().for_each(|(c, square)| {
            map.entry(square.flip()).or_insert_with(|| c.to_ascii_uppercase());
        });

        map
    };
}

pub fn parse_fen(input: &str) -> Result<DenseBoard, PacoError> {
    if let Some((_, pieces, player, move_count, castling, en_passant)) = regex(input) {
        let mut result = DenseBoard::empty();

        // Iterate over all the rows and insert pieces.
        for (v, row) in pieces.split('/').enumerate() {
            let mut h = 0;
            for char in row.chars() {
                if let Some(square) = CHAR_TO_SQUARE.get(&char) {
                    let position = 56 + h - 8 * v;
                    if position >= 64 {
                        panic!("Position too large: {}", position);
                    }
                    result
                        .substrate
                        .set_square(BoardPosition(position as u8), *square);
                    h += 1;
                }
                // Or look at a number and do many empty squares
                else if let Some(n) = char.to_digit(10) {
                    h += n as usize;
                }
            }
            // Check if we are done.
            if h != 8 {
                return Err(PacoError::InputFenMalformed(format!(
                    "Line {} has length {}",
                    v, h
                )));
            }
        }

        // Set other metadata
        result.controlling_player = match player {
            "w" => PlayerColor::White,
            "b" => PlayerColor::Black,
            _ => unreachable!("Regex restricts input to 'w' and 'b'."),
        };
        result.draw_state.no_progress_half_moves = move_count.parse().unwrap();
        result.castling = Castling::from_string(castling);
        result.en_passant = BoardPosition::try_from(en_passant).ok();

        Ok(result)
    } else {
        Err(PacoError::InputFenMalformed(
            "Regex didn't match fen string.".to_string(),
        ))
    }
}

pub fn write_fen(input: &DenseBoard) -> String {
    use std::fmt::Write as _;
    let mut result = String::new();

    for v in 0..=7 {
        let mut running_empty_spaces = 0;
        for h in 0..=7 {
            let position = 56 + h - 8 * v;
            let square = input.substrate.get_square(BoardPosition(position as u8));
            if square.is_empty() {
                running_empty_spaces += 1;
            } else if let Some(char) = SQUARE_TO_CHAR.get(&square) {
                if running_empty_spaces > 0 {
                    write!(result, "{}", running_empty_spaces).unwrap();
                    running_empty_spaces = 0;
                }
                result.push(*char);
            } else {
                panic!("Can't encode square: {:?}", square);
            }
        }
        if running_empty_spaces > 0 {
            write!(result, "{}", running_empty_spaces).unwrap();
        }
        if v != 7 {
            write!(result, "/").unwrap();
        }
    }

    write!(
        result,
        " {} {} {} {} -",
        if input.controlling_player == PlayerColor::White {
            'w'
        } else {
            'b'
        },
        input.draw_state.no_progress_half_moves,
        input.castling,
        input
            .en_passant
            .map(|sq| sq.to_string())
            .unwrap_or_else(|| "-".to_owned()),
    )
    .unwrap();

    result
}

/// Build the map that contains mappings like 'a' -> (Pawn, Pawn)
#[rustfmt::skip]
fn lowercase_char_to_square() -> HashMap<char, Square> {
    use crate::PieceType::*;
    let mut result = HashMap::new();
    result.insert('p', Square { white: None,         black: Some(Pawn)});
    result.insert('r', Square { white: None,         black: Some(Rook)});
    result.insert('n', Square { white: None,         black: Some(Knight)});
    result.insert('b', Square { white: None,         black: Some(Bishop)});
    result.insert('q', Square { white: None,         black: Some(Queen)});
    result.insert('k', Square { white: None,         black: Some(King)});
    result.insert('a', Square { black: Some(Pawn),   white: Some(Pawn)});
    result.insert('c', Square { black: Some(Pawn),   white: Some(Rook)});
    result.insert('d', Square { black: Some(Pawn),   white: Some(Knight)});
    result.insert('e', Square { black: Some(Pawn),   white: Some(Bishop)});
    result.insert('f', Square { black: Some(Pawn),   white: Some(Queen)});
    result.insert('g', Square { black: Some(Pawn),   white: Some(King)});
    result.insert('h', Square { black: Some(Rook),   white: Some(Rook)});
    result.insert('i', Square { black: Some(Rook),   white: Some(Knight)});
    result.insert('j', Square { black: Some(Rook),   white: Some(Bishop)});
    result.insert('l', Square { black: Some(Rook),   white: Some(Queen)});
    result.insert('m', Square { black: Some(Rook),   white: Some(King)});
    result.insert('o', Square { black: Some(Knight), white: Some(Knight)});
    result.insert('s', Square { black: Some(Knight), white: Some(Bishop)});
    result.insert('t', Square { black: Some(Knight), white: Some(Queen)});
    result.insert('u', Square { black: Some(Knight), white: Some(King)});
    result.insert('v', Square { black: Some(Bishop), white: Some(Bishop)});
    result.insert('w', Square { black: Some(Bishop), white: Some(Queen)});
    result.insert('x', Square { black: Some(Bishop), white: Some(King)});
    result.insert('y', Square { black: Some(Queen),  white: Some(Queen)});
    result.insert('z', Square { black: Some(Queen),  white: Some(King)});
    result.insert('_', Square { black: Some(King),   white: Some(King)});
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::DenseBoard;
    use crate::PacoAction;
    use crate::PacoBoard;

    /// Helper macro to execute moves in unit tests.
    macro_rules! execute_action {
        ($board:expr, lift, $square:expr) => {{
            $board
                .execute_trusted(PacoAction::Lift($square.try_into().unwrap()))
                .unwrap();
        }};
        ($board:expr, place, $square:expr) => {{
            $board
                .execute_trusted(PacoAction::Place($square.try_into().unwrap()))
                .unwrap();
        }};
        ($board:expr, promote, $pieceType:expr) => {{
            $board
                .execute_trusted(PacoAction::Promote($pieceType))
                .unwrap();
        }};
    }

    /// Test that the new empty is properly serialized and deserialized.
    #[test]
    fn empty_board() {
        let fen_string = "8/8/8/8/8/8/8/8 w 0 AHah - -";
        let board = parse_fen(fen_string).unwrap();
        assert_eq!(board, DenseBoard::empty());
        assert_eq!(write_fen(&board), fen_string);
    }

    /// Test that the new board is properly serialized and deserialized.
    #[test]
    fn new_board() {
        let fen_string = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w 0 AHah - -";
        let board = parse_fen(fen_string).unwrap();
        assert_eq!(board, DenseBoard::new());
        assert_eq!(write_fen(&board), fen_string);
    }

    #[test]
    fn en_passant() {
        let mut board = DenseBoard::new();
        // Advance a white pawn.
        execute_action!(board, lift, "d2");
        execute_action!(board, place, "d4");
        assert_eq!(board.en_passant.unwrap().to_string(), "d3");

        let fen_string = "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b 1 AHah d3 -";
        assert_eq!(write_fen(&board), fen_string);
        assert_eq!(board, parse_fen(fen_string).unwrap());

        // Advance a black pawn.
        execute_action!(board, lift, "f7");
        execute_action!(board, place, "f5");
        assert_eq!(board.en_passant.unwrap().to_string(), "f6");

        let fen_string = "rnbqkbnr/ppppp1pp/8/5p2/3P4/8/PPP1PPPP/RNBQKBNR w 2 AHah f6 -";
        assert_eq!(write_fen(&board), fen_string);
        assert_eq!(board, parse_fen(fen_string).unwrap());
    }

    /// Generate some random boards and roundtrip them through the serialization
    #[test]
    fn roundtrip() {
        use rand::{thread_rng, Rng};

        let mut rng = thread_rng();
        for _ in 0..1000 {
            let board: DenseBoard = rng.gen();
            let fen = write_fen(&board);
            println!("Fen: {}", fen);
            let board_after_roundtrip = parse_fen(&fen).unwrap();
            assert_eq!(board, board_after_roundtrip);
        }
    }
}
