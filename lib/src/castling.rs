//! This module encapsulates data for castling and decisions for castling.
//! During castling the King moves from its initial file into the C or G file.
//! The corresponding Rook moves into the D or F file. This is true for Fischer
//! random chess as well.
//!
//! All squares the King passes through must be safe (non-threatened).
//! Only the Rook and King may occupy the squares they pass through.
//!
//! To tell the player that they can castle, we create place actions while the
//! King is in hand.
//!
//! For the traditional starting position, these are shown on the King target
//! positions. This does not work for Fischer random chess, as moving and
//! castling can go to the same position.

use crate::{
    const_tile::A1,
    substrate::BitBoard,
    types::{BoardFile, BoardRank},
    BoardPosition, PacoError, PlayerColor,
};
use serde::{Deserialize, Serialize};

/// The Castling struct encodes the castling options left for the players.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Castling {
    pub white_queen_side: CompactCastlingIdentifier,
    pub white_king_side: CompactCastlingIdentifier,
    pub black_queen_side: CompactCastlingIdentifier,
    pub black_king_side: CompactCastlingIdentifier,
}

impl Default for Castling {
    /// Returns an initial Castling where all castling options are possible
    /// This is for the default position.
    fn default() -> Self {
        Castling {
            white_queen_side: Castling::WHITE_QUEEN,
            white_king_side: Castling::WHITE_KING,
            black_queen_side: Castling::BLACK_QUEEN,
            black_king_side: Castling::BLACK_KING,
        }
    }
}

impl Castling {
    pub const FORFEIT: CompactCastlingIdentifier = CompactCastlingIdentifier(0);

    pub const WHITE_QUEEN: CompactCastlingIdentifier = CompactCastlingIdentifier(0b10_000_100);
    pub const WHITE_KING: CompactCastlingIdentifier = CompactCastlingIdentifier(0b10_111_100);
    pub const BLACK_QUEEN: CompactCastlingIdentifier = CompactCastlingIdentifier(0b11_000_100);
    pub const BLACK_KING: CompactCastlingIdentifier = CompactCastlingIdentifier(0b11_111_100);

    /// Returns a Castling where no castling is posible anymore.
    pub fn forfeit() -> Self {
        Castling {
            white_queen_side: Castling::FORFEIT,
            white_king_side: Castling::FORFEIT,
            black_queen_side: Castling::FORFEIT,
            black_king_side: Castling::FORFEIT,
        }
    }

    /// Returns a Castling for Fischer random chess.
    pub fn fischer(left_rook: BoardFile, king: BoardFile, right_rook: BoardFile) -> Castling {
        Castling {
            white_queen_side: CompactCastlingIdentifier::new(king, left_rook, PlayerColor::White),
            white_king_side: CompactCastlingIdentifier::new(king, right_rook, PlayerColor::White),
            black_queen_side: CompactCastlingIdentifier::new(king, left_rook, PlayerColor::Black),
            black_king_side: CompactCastlingIdentifier::new(king, right_rook, PlayerColor::Black),
        }
    }

    /// Returns the two options for castling for the given player.
    pub fn options(&self, color: PlayerColor) -> [CompactCastlingIdentifier; 2] {
        match color {
            PlayerColor::White => [self.white_queen_side, self.white_king_side],
            PlayerColor::Black => [self.black_queen_side, self.black_king_side],
        }
    }

    pub fn forfeit_rights_for_lifting_rook(&mut self, position: BoardPosition) {
        self.white_queen_side
            .forfeit_rights_for_lifting_rook(position);
        self.white_king_side
            .forfeit_rights_for_lifting_rook(position);
        self.black_queen_side
            .forfeit_rights_for_lifting_rook(position);
        self.black_king_side
            .forfeit_rights_for_lifting_rook(position);
    }

    pub fn remove_rights_for_color(&mut self, current_player: PlayerColor) {
        match current_player {
            PlayerColor::White => {
                self.white_queen_side = Castling::FORFEIT;
                self.white_king_side = Castling::FORFEIT;
            }
            PlayerColor::Black => {
                self.black_queen_side = Castling::FORFEIT;
                self.black_king_side = Castling::FORFEIT;
            }
        }
    }

    /// Expect a castling string like "Aah" and king positions.
    /// We take two king positions, to be more flexible than Fischer random chess.
    /// This means we can accept more FEN strings than just Fischer random chess.
    /// We also become compatible with both sides being independently randomized.
    pub fn from_fen(
        fen: &str,
        white_king: BoardFile,
        black_king: BoardFile,
    ) -> Result<Castling, PacoError> {
        let mut castling = Castling::forfeit();
        for char in fen.chars() {
            if char == '-' {
                return Ok(Castling::forfeit());
            }
            Castling::from_fen_char(char, white_king, black_king, &mut castling)?;
        }
        Ok(castling)
    }

    fn from_fen_char(
        letter: char,
        white_king: BoardFile,
        black_king: BoardFile,
        castling: &mut Castling,
    ) -> Result<(), PacoError> {
        let Some((rook_file, color)) = BoardFile::from_char(letter) else {
            return Err(PacoError::InputFenMalformed(format!(
                "Invalid fen character '{letter}'."
            )));
        };

        let king_file = if color.is_white() {
            white_king
        } else {
            black_king
        };

        let compact_id = CompactCastlingIdentifier::new(king_file, rook_file, color);

        // Assign to the appropriate field based on the side and color
        if color.is_white() {
            if (rook_file as u8) < (king_file as u8) {
                // Queen side
                castling.white_queen_side = compact_id;
            } else {
                // King side
                castling.white_king_side = compact_id;
            }
        } else if (rook_file as u8) < (king_file as u8) {
            // Queen side
            castling.black_queen_side = compact_id;
        } else {
            // King side
            castling.black_king_side = compact_id;
        }

        Ok(())
    }

    pub fn into_fen(self) -> String {
        let mut result = String::new();
        push_fen_identifier_name(&mut result, self.white_queen_side);
        push_fen_identifier_name(&mut result, self.white_king_side);
        push_fen_identifier_name(&mut result, self.black_queen_side);
        push_fen_identifier_name(&mut result, self.black_king_side);
        if result.is_empty() {
            result.push('-');
        }
        result
    }
}

/// Pushes the FEN identifier of the castling option into a string we are building.
/// This is the file the rook is on, upper case for white, lower case for black.
fn push_fen_identifier_name(result: &mut String, side: CompactCastlingIdentifier) {
    if side.is_available() {
        let char = CastlingIdentifier::from_compact(side).rook_file.to_char();
        result.push(if side.color().is_white() {
            char.to_ascii_uppercase()
        } else {
            char
        });
    }
}

/// The three least significant bits encode the king file, the next three bits
/// the rook file. Bit seven encodes the player color. Bit 8 encodes validity.
/// This means our format is `0b_1prrrkkk` is the format.
/// Not all 7 bit strings are valid, but all valid castling identifiers can be
/// encoded in 7 bits. This means there are less than 128 valid identifiers.
/// To encode "this castling option is forfeit" use all zeros.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct CompactCastlingIdentifier(u8);

impl CompactCastlingIdentifier {
    pub fn new(king: BoardFile, rook: BoardFile, color: PlayerColor) -> CompactCastlingIdentifier {
        let king_file_bits = king as u8;
        let rook_file_bits = (rook as u8) << 3;
        let color_bit = (color as u8) << 6;
        // Set the availability bit (bit 7) to 1
        let availability_bit = 0b1000_0000;

        CompactCastlingIdentifier(availability_bit | color_bit | rook_file_bits | king_file_bits)
    }

    const fn color(&self) -> PlayerColor {
        PlayerColor::expect_u8((self.0 & 0b0100_0000) >> 6)
    }

    /// As the leadign bit is always 1, we need to chop it off before we can
    /// index into the memoized array.
    const fn index(&self) -> usize {
        (self.0 & 0b0111_1111) as usize
    }
    pub fn is_available(&self) -> bool {
        self.0 & 0b1000_0000 != 0
    }

    /// If the rook being lifted matches this castling option, then we forfeit
    /// the castling option.
    fn forfeit_rights_for_lifting_rook(&mut self, position: BoardPosition) {
        if let Some(details) = get_castling_details(*self) {
            if details.rook_from == position {
                *self = Castling::FORFEIT;
            }
        }
    }

    const fn is_normal_castling(self) -> bool {
        Castling::WHITE_QUEEN.0 == self.0
            || Castling::WHITE_KING.0 == self.0
            || Castling::BLACK_QUEEN.0 == self.0
            || Castling::BLACK_KING.0 == self.0
    }
}

#[derive(Clone, Copy)]
struct CastlingIdentifier {
    king_file: BoardFile,
    rook_file: BoardFile,
}

impl CastlingIdentifier {
    const fn from_compact(cci: CompactCastlingIdentifier) -> CastlingIdentifier {
        let king_file = BoardFile::expect_u8(cci.0 & 0b111);
        let rook_file = BoardFile::expect_u8((cci.0 >> 3) & 0b111);
        CastlingIdentifier {
            king_file,
            rook_file,
        }
    }
}

/// For a castling move, the details to check if the move is legal and to execute it.
#[derive(Clone, Copy, Debug)]
pub struct CastlingDetails {
    pub king_from: BoardPosition,
    pub king_to: BoardPosition,
    pub rook_from: BoardPosition,
    pub rook_to: BoardPosition,
    /// The place action target square for triggering the castling.
    /// For normal castling, this is the king_to. Otherwise, it is the rook_from.
    /// This makes sure we are downward compatible with regular paco sako but
    /// also avoid ambiguity with regular king moves.
    pub place_target: BoardPosition,
    /// The squares either piece passes through, minus the start squares
    pub must_be_empty: BitBoard,
    pub must_be_safe: BitBoard,
}

impl CastlingDetails {
    pub fn is_king_side(&self) -> bool {
        // If the rook file is to the right of the king file, it is king-side.
        (self.rook_from.file() as u8) > (self.king_from.file() as u8)
    }
}

const fn file_range(a: BoardFile, b: BoardFile, rank: BoardRank) -> BitBoard {
    let mut range = BitBoard::empty();
    let (min_file, max_file) = if (a as u8) < (b as u8) {
        (a as u8, b as u8)
    } else {
        (b as u8, a as u8)
    };
    let mut current_file = min_file;
    while current_file <= max_file {
        range.insert(BoardPosition::new(current_file, rank as u8));
        current_file += 1;
    }
    range
}

/// From the compact representation of a castling move, create the details for the move.
const fn details_from_identifier(
    id: CastlingIdentifier,
    color: PlayerColor,
    is_normal: bool,
) -> CastlingDetails {
    // Is this queen side or king side?
    let (king_to_file, rook_to_file) = if (id.rook_file as u8) < (id.king_file as u8) {
        (BoardFile::FileC, BoardFile::FileD)
    } else {
        (BoardFile::FileG, BoardFile::FileF)
    };

    let home_rank = color.home_rank();
    let must_be_safe = file_range(id.king_file, king_to_file, home_rank);
    let mut must_be_empty = file_range(id.rook_file, rook_to_file, home_rank);
    must_be_empty.insert_all(must_be_safe);
    must_be_empty.remove(BoardPosition::new(id.king_file as u8, home_rank as u8));
    must_be_empty.remove(BoardPosition::new(id.rook_file as u8, home_rank as u8));

    let king_to = BoardPosition::new(king_to_file as u8, home_rank as u8);
    let rook_from = BoardPosition::new(id.rook_file as u8, home_rank as u8);
    CastlingDetails {
        king_from: BoardPosition::new(id.king_file as u8, home_rank as u8),
        king_to,
        rook_from,
        rook_to: BoardPosition::new(rook_to_file as u8, home_rank as u8),
        place_target: if is_normal { king_to } else { rook_from },
        must_be_empty,
        must_be_safe,
    }
}

/// Convert a u8 directly to CastlingDetails through the conversion pipeline
const fn details_from_u8(encoded: u8) -> CastlingDetails {
    let compact = CompactCastlingIdentifier(encoded);
    let color = compact.color();
    let id = CastlingIdentifier::from_compact(compact);
    details_from_identifier(id, color, compact.is_normal_castling())
}

/// A precomputed lookup table for all 128 possible castling details
static CASTLING_DETAILS: [CastlingDetails; 128] = {
    let mut details = [CastlingDetails {
        king_from: A1,
        king_to: A1,
        rook_from: A1,
        rook_to: A1,
        place_target: A1,
        must_be_empty: BitBoard::empty(),
        must_be_safe: BitBoard::empty(),
    }; 128];

    let mut i = 0;
    while i < 128 {
        details[i] = details_from_u8(i as u8 | 0b1000_0000);
        i += 1;
    }

    details
};

/// Get the castling details for a compact castling identifier
pub fn get_castling_details(cci: CompactCastlingIdentifier) -> Option<CastlingDetails> {
    if cci.is_available() {
        Some(CASTLING_DETAILS[cci.index()])
    } else {
        None
    }
}

#[cfg(test)]
mod test {
    use super::*;
    use crate::ai::repr;
    use crate::const_tile::*;
    use crate::PacoAction::{Lift, Place};
    use crate::{fen, PacoBoard, RequiredAction};

    macro_rules! file_range_tests {
        ($($name:ident: $input:expr => $expected:expr,)*) => {
            $(
                #[test]
                fn $name() {
                    let (file_a, file_b, rank) = $input;
                    let range = file_range(file_a, file_b, rank);
                    assert_eq!(range, BitBoard($expected));
                }
            )*
        }
    }

    file_range_tests! {
        file_range_a_to_c_rank1: (BoardFile::FileA, BoardFile::FileC, BoardRank::Rank1) => 0b111,
        file_range_e_to_h_rank1: (BoardFile::FileE, BoardFile::FileH, BoardRank::Rank1) => 0b11110000,
        file_range_e_to_h_rank3: (BoardFile::FileE, BoardFile::FileH, BoardRank::Rank3) => 0b11110000 << (2 * 8),
        file_range_a_to_a_rank8: (BoardFile::FileA, BoardFile::FileA, BoardRank::Rank8) => 0b1 << (7 * 8),
        file_range_d_to_f_rank5: (BoardFile::FileD, BoardFile::FileF, BoardRank::Rank5) => 0b111000 << (4 * 8),
    }

    #[test]
    fn file_range_order_doesn_matter() {
        for i in 0..8 {
            for j in 0..8 {
                let file_a = BoardFile::expect_u8(i);
                let file_b = BoardFile::expect_u8(j);
                let rank = BoardRank::Rank1;
                let range_a_to_b = file_range(file_a, file_b, rank);
                let range_b_to_a = file_range(file_b, file_a, rank);
                assert_eq!(range_a_to_b, range_b_to_a);
            }
        }
    }

    #[test]
    fn test_castling_details_lookup() {
        // Test for white player, king on E1, rook on A1 (standard queen-side castling)
        let white_queen_side = CompactCastlingIdentifier(0b10_000_100); // White: 0, rook file A: 000, king file E: 100
        let details = get_castling_details(white_queen_side).expect("Castling details not found");

        // King should move from E1 to C1
        assert_eq!(details.king_from, E1);
        assert_eq!(details.king_to, C1);
        assert_eq!(details.must_be_safe, BitBoard(0b_11100));

        // Rook should move from A1 to D1
        assert_eq!(details.rook_from, A1);
        assert_eq!(details.rook_to, D1);
        assert_eq!(details.must_be_empty, BitBoard(0b_01110));

        // Test for black player, king on E8, rook on H8 (standard king-side castling)
        let black_king_side = CompactCastlingIdentifier(0b11_111_100); // Black: 1, rook file H: 111, king file E: 100
        let details = get_castling_details(black_king_side).expect("Castling details not found");

        // King should move from E8 to G8
        assert_eq!(details.king_from, E8);
        assert_eq!(details.king_to, G8);
        assert_eq!(details.must_be_safe, BitBoard(0b_01110000 << (7 * 8)));

        // Rook should move from H8 to F8
        assert_eq!(details.rook_from, H8);
        assert_eq!(details.rook_to, F8);
        assert_eq!(details.must_be_empty, BitBoard(0b_01100000 << (7 * 8)));
    }

    #[test]
    fn test_direct_vs_lookup_equality() {
        for i in 0..128 {
            let compact = CompactCastlingIdentifier(i | 0b10_000_000);
            let direct = {
                let color = compact.color();
                let id = CastlingIdentifier::from_compact(compact);
                details_from_identifier(id, color, compact.is_normal_castling())
            };
            let from_lookup = get_castling_details(compact).expect("Castling details not found");

            assert_eq!(direct.king_from.0, from_lookup.king_from.0);
            assert_eq!(direct.king_to.0, from_lookup.king_to.0);
            assert_eq!(direct.rook_from.0, from_lookup.rook_from.0);
            assert_eq!(direct.rook_to.0, from_lookup.rook_to.0);
            assert_eq!(direct.must_be_empty.0, from_lookup.must_be_empty.0);
            assert_eq!(direct.must_be_safe.0, from_lookup.must_be_safe.0);
        }
    }

    #[test]
    fn default_fen() {
        let castling = Castling::default();
        let fen = castling.into_fen();
        assert_eq!(fen, "AHah");

        let parsed_castling = Castling::from_fen("AHah", BoardFile::FileE, BoardFile::FileE)
            .expect("Fen didn't parse as expected");
        assert_eq!(castling, parsed_castling);
    }

    #[test]
    fn test_fischer_castling() {
        let castling = Castling::fischer(BoardFile::FileD, BoardFile::FileE, BoardFile::FileF);
        let fen = castling.into_fen();
        assert_eq!(fen, "DFdf");
        assert_eq!(castling.white_queen_side.0, 0b10_011_100);
        assert_eq!(castling.white_king_side.0, 0b10_101_100);
        assert_eq!(castling.black_queen_side.0, 0b11_011_100);
        assert_eq!(castling.black_king_side.0, 0b11_101_100);
    }

    #[test]
    fn castling_properly_decoded_from_fen() -> Result<(), PacoError> {
        let board = fen::parse_fen("nbbrqnkr/pppppppp/8/8/8/8/PPPPPPPP/NBBRQNKR w 0 DHdh - -")?;
        let wks = get_castling_details(board.castling.white_king_side).unwrap();

        assert_eq!(wks.king_from, G1);
        assert_eq!(wks.king_to, G1);
        assert_eq!(wks.rook_from, H1);
        assert_eq!(wks.rook_to, F1);
        assert_eq!(wks.place_target, H1);

        Ok(())
    }

    #[test]
    fn info_fen_and_from_fen_match() {
        for left_rook in 0..6 {
            for king in (left_rook + 1)..7 {
                for right_rook in (king + 1)..8 {
                    let castling = Castling::fischer(
                        BoardFile::expect_u8(left_rook),
                        BoardFile::expect_u8(king),
                        BoardFile::expect_u8(right_rook),
                    );
                    let fen = castling.into_fen();
                    let parsed_castling = Castling::from_fen(
                        &fen,
                        BoardFile::expect_u8(king),
                        BoardFile::expect_u8(king),
                    )
                        .expect("Fen didn't parse as expected");
                    assert_eq!(castling, parsed_castling);
                }
            }
        }
    }

    /// This macro executes a sequence of actions, the first being a lift action
    /// and the rest being place actions.
    /// You can't use it for promotions.
    macro_rules! do_move {
    ($board:expr, $from:expr, $($to:expr),+) => {
        {
            $board.execute(Lift($from)).expect("Lift action failed");
            $(
                $board.execute(Place($to)).expect("Place action failed");
            )+
        }
    };
}

    /// This reproduces a case where castling was incorrectly implemented and the rook was
    /// replaced by the king.
    #[test]
    fn king_should_not_eat_rook() -> Result<(), PacoError> {
        let mut board = fen::parse_fen("brnbnqkr/pppppppp/8/8/8/8/PPPPPPPP/BRNBNQKR w 0 BHbh - -")?;

        do_move!(board, C1, D3);
        do_move!(board, E8, D6);
        do_move!(board, E1, F3);
        do_move!(board, E7, E5);
        do_move!(board, E2, E4);
        do_move!(board, D8, H4);
        do_move!(board, F3, G5);
        do_move!(board, C8, E7);
        do_move!(board, D3, F4);
        do_move!(board, E7, F5);
        do_move!(board, F1, C4);
        do_move!(board, D6, C4); // union
        do_move!(board, D1, E2);
        do_move!(board, C4, B6);
        do_move!(board, G1, B1);

        println!("{:?}", fen::write_fen(&board));
        assert_eq!(
            fen::write_fen(&board),
            "br3qkr/pppp1ppp/1t6/4pnN1/4PN1b/8/PPPPBPPP/B1KR3R b 3 bh - -"
        );

        let mut out = [0; 38];
        repr::index_representation(&board, &mut out);

        Ok(())
    }

    #[test]
    fn king_should_not_eat_rook2() -> Result<(), PacoError> {
        let mut board = fen::parse_fen("nnrkqrbb/pppppppp/8/8/8/8/PPPPPPPP/NNRKQRBB w 0 CFcf - -")?;

        do_move!(board, F2, F4);
        do_move!(board, B8, C6);
        do_move!(board, E1, H4);
        do_move!(board, F7, F6);
        do_move!(board, G1, B6);
        do_move!(board, E8, G6);
        do_move!(board, D1, F1); // O-O

        println!("{:?}", fen::write_fen(&board));
        assert_eq!(
            fen::write_fen(&board),
            "n1rk1rbb/ppppp1pp/1Bn2pq1/8/5P1Q/8/PPPPP1PP/NNR2RKB b 7 cf - -"
        );

        let mut out = [0; 38];
        repr::index_representation(&board, &mut out);

        do_move!(board, C6, E5);

        assert_eq!(board.required_action, RequiredAction::Lift);

        Ok(())
    }
}
