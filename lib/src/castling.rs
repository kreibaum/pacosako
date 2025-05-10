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
    substrate::BitBoard,
    types::{BoardFile, BoardRank},
    BoardPosition, PlayerColor,
};
use serde::{Deserialize, Serialize};
use std::fmt::Display;

#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Castling {
    pub white_queen_side: bool,
    pub white_king_side: bool,
    pub black_queen_side: bool,
    pub black_king_side: bool,
}

impl Castling {
    /// Returns an initial Castling structure where all castling options are possible
    pub fn new() -> Self {
        Castling {
            white_queen_side: true,
            white_king_side: true,
            black_queen_side: true,
            black_king_side: true,
        }
    }

    pub fn remove_rights_for_color(&mut self, current_player: PlayerColor) {
        match current_player {
            PlayerColor::White => {
                self.white_queen_side = false;
                self.white_king_side = false;
            }
            PlayerColor::Black => {
                self.black_queen_side = false;
                self.black_king_side = false;
            }
        }
    }

    pub fn from_string(input: &str) -> Self {
        Castling {
            white_queen_side: input.contains('A'),
            white_king_side: input.contains('H'),
            black_queen_side: input.contains('a'),
            black_king_side: input.contains('h'),
        }
    }
}

impl Display for Castling {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let mut any_char = false;
        if self.white_queen_side {
            write!(f, "A")?;
            any_char = true;
        }
        if self.white_king_side {
            write!(f, "H")?;
            any_char = true;
        }
        if self.black_queen_side {
            write!(f, "a")?;
            any_char = true;
        }
        if self.black_king_side {
            write!(f, "h")?;
            any_char = true;
        }
        if !any_char {
            write!(f, "-")?;
        }
        Ok(())
    }
}

/// The three least significant bits encode the king file, the next three bits
/// the rook file. Bit seven encodes the player color. Bit 8 encodes validity.
/// This means our format is `0b_1prrrkkk` is the format.
/// Not all 7 bit strings are valid, but all valid castling identifiers can be
/// encoded in 7 bits. This means there are less than 128 valid identifiers.
/// To encode "this castling option is forfeit" use all zeros.
#[derive(Clone, Copy)]
pub struct CompactCastlingIdentifier(u8);

impl CompactCastlingIdentifier {
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
#[derive(Clone, Copy)]
pub struct CastlingDetails {
    pub king_from: BoardPosition,
    pub king_to: BoardPosition,
    pub rook_from: BoardPosition,
    pub rook_to: BoardPosition,
    // The squares either piece passes through, minus the start squares
    pub must_be_empty: BitBoard,
    pub must_be_safe: BitBoard,
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
const fn details_from_identifier(id: CastlingIdentifier, color: PlayerColor) -> CastlingDetails {
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

    CastlingDetails {
        king_from: BoardPosition::new(id.king_file as u8, home_rank as u8),
        king_to: BoardPosition::new(king_to_file as u8, home_rank as u8),
        rook_from: BoardPosition::new(id.rook_file as u8, home_rank as u8),
        rook_to: BoardPosition::new(rook_to_file as u8, home_rank as u8),
        must_be_empty,
        must_be_safe,
    }
}

/// Convert a u8 directly to CastlingDetails through the conversion pipeline
const fn details_from_u8(encoded: u8) -> CastlingDetails {
    let compact = CompactCastlingIdentifier(encoded);
    let color = compact.color();
    let id = CastlingIdentifier::from_compact(compact);
    details_from_identifier(id, color)
}

/// A precomputed lookup table for all 128 possible castling details
static CASTLING_DETAILS: [CastlingDetails; 128] = {
    let mut details = [CastlingDetails {
        king_from: BoardPosition::new(0, 0),
        king_to: BoardPosition::new(0, 0),
        rook_from: BoardPosition::new(0, 0),
        rook_to: BoardPosition::new(0, 0),
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
pub fn get_castling_details(cci: CompactCastlingIdentifier) -> CastlingDetails {
    CASTLING_DETAILS[cci.index()]
}

#[cfg(test)]
mod test {
    use super::*;
    use crate::const_tile::*;

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
        let white_queen_side = CompactCastlingIdentifier(0b0_000_100); // White: 0, rook file A: 000, king file E: 100
        let details = get_castling_details(white_queen_side);

        // King should move from E1 to C1
        assert_eq!(details.king_from, E1);
        assert_eq!(details.king_to, C1);
        assert_eq!(details.must_be_safe, BitBoard(0b_11100));

        // Rook should move from A1 to D1
        assert_eq!(details.rook_from, A1);
        assert_eq!(details.rook_to, D1);
        assert_eq!(details.must_be_empty, BitBoard(0b_01110));

        // Test for black player, king on E8, rook on H8 (standard king-side castling)
        let black_king_side = CompactCastlingIdentifier(0b0_111_100 | 0b0100_0000); // Black: 1, rook file H: 111, king file E: 100
        let details = get_castling_details(black_king_side);

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
            let compact = CompactCastlingIdentifier(i);
            let direct = {
                let color = compact.color();
                let id = CastlingIdentifier::from_compact(compact);
                details_from_identifier(id, color)
            };
            let from_lookup = get_castling_details(compact);

            assert_eq!(direct.king_from.0, from_lookup.king_from.0);
            assert_eq!(direct.king_to.0, from_lookup.king_to.0);
            assert_eq!(direct.rook_from.0, from_lookup.rook_from.0);
            assert_eq!(direct.rook_to.0, from_lookup.rook_to.0);
            assert_eq!(direct.must_be_empty.0, from_lookup.must_be_empty.0);
            assert_eq!(direct.must_be_safe.0, from_lookup.must_be_safe.0);
        }
    }
}
