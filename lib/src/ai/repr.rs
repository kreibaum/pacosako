//! Board representation as a 8x8x30 tensor. Or a list of indices which are 1.
//!
//! We have 30 layers on 8x8 tiles.
//!
//! The first 24 layers are the pieces:
//!     (Pawn, Rook, Knight, Bishop, Queen, King) x (Mine, Opponent) x (settled, lifted)
//! Then there is one layer (24) where the en passant square is set to 1, if there is one.
//! The next four layers are the castling rights:
//!     (25: My Queen, 26: My King, 27: Their Queen, 28: Their King)
//! Then there is one layer that holds a float in [0, 1] that represents the half move clock.
//!
//! Where Mine/Opponent map to White/Black depending on the controlling player.
//!
//! Settled: 0-11
//!   Mine: 0-5
//!     Pawn: Layer 0
//!     ...
//!     King: Layer 5
//!   Opponent: 6-11
//! Lifted: 12-23
//!   Mine: 12-17
//!   Opponent: 18-23
//! En passant: 24
//! Castling: 25-28
//! Half move clock: 29
//!
//! The first 24 layers are mostly zero, there is at most one 1 per piece.
//! On an ordinary game, that would be 32 1s. Variants with more pieces are out of scope.
//!
//! Indices are 0-indexed. To transmit "no en passant", we reuse one of the
//! previous indices.
//!
//! 32 x index, index or 0, 4 x bool, 0..100 half move clock
//!
//! We represent "index" as a u32.
//! We represent "bool" as 0u32 or 1u32.
//! We represent "half move clock" as a u32 in [0, 100].
//!
//! This means we deliver a list of 38 u32s.
//!
//! To convert this into a tensor, we do the following:
//!
//! Initialize a 8*8*30 tensor with zeros.
//! tensor[indices[0:32]] = 1.0, where we index into tensor with the indices.
//! tensor[:,:,25] = indices[33] as f32
//! tensor[:,:,26] = indices[34] as f32
//! tensor[:,:,27] = indices[35] as f32
//! tensor[:,:,28] = indices[36] as f32
//! tensor[:,:,29] = indices[37] as f32 / 100.0
//!

use crate::{
    castling::Castling, substrate::Substrate, BoardPosition, DenseBoard, PacoBoard, PieceType,
    PlayerColor,
};

/// Fills in the tensor representation of the board.
/// Assumes that out is already zeroed.
#[allow(clippy::needless_range_loop)]
pub fn tensor_representation(board: &DenseBoard, out: &mut [f32; 8 * 8 * 30]) {
    let mut idxrepr = [0; 38];
    index_representation(board, &mut idxrepr);

    for i in 0..=32 {
        let idx = idxrepr[i] as usize;
        out[idx] = 1.0;
    }

    for i in 33..=36 {
        if idxrepr[i] == 1 {
            for j in 0..64 {
                out[(i - 8) * 64 + j] = 1.0;
            }
        }
    }

    for j in 0..64 {
        out[29 * 64 + j] = idxrepr[37] as f32 / 100.0;
    }
}

pub fn index_representation(board: &DenseBoard, out: &mut [u32; 38]) {
    let mut out = Output::new(out, board.controlling_player());

    // Pieces that are settled on the board. This should be between 30 and 32.
    for piece_color in PlayerColor::all() {
        for tile in BoardPosition::all() {
            if let Some(piece_type) = board.substrate.get_piece(piece_color, tile) {
                out.push_index(tile, piece_type, piece_color, false);
            }
        }
    }
    assert!(out.index <= 32);
    assert!(out.index >= 30);

    // Pieces that are currently lifted. Afterwards there are always 32 pieces.
    match board.lifted_piece {
        crate::Hand::Empty => {}
        crate::Hand::Single { piece, position } => {
            out.push_index(position, piece, board.controlling_player(), true);
        }
        crate::Hand::Pair {
            piece,
            partner,
            position,
        } => {
            out.push_index(position, piece, board.controlling_player(), true);
            out.push_index(position, partner, board.controlling_player().other(), true);
        }
    }
    assert!(out.index == 32);

    // En passant square.
    out.push_en_passant(board.en_passant);

    // Castling rights.
    out.push_castling(board.castling);

    // Half move clock.
    out.push(board.draw_state.no_progress_half_moves as u32);

    assert!(out.index == 38);
}

/// A little wrapper around a mutable slice of u32s, so we can use it like a vector.
struct Output<'a> {
    storage: &'a mut [u32; 38],
    index: usize,
    viewpoint_color: PlayerColor,
}

impl<'a> Output<'a> {
    fn new(storage: &'a mut [u32; 38], viewpoint_color: PlayerColor) -> Self {
        Self {
            storage,
            index: 0,
            viewpoint_color,
        }
    }
    fn push(&mut self, value: u32) {
        self.storage[self.index] = value;
        self.index += 1;
    }

    /// Push a boolean value either as 0u32 or 1u32.
    fn push_bool(&mut self, value: bool) {
        self.push(u32::from(value));
    }

    fn push_index(
        &mut self,
        tile: BoardPosition,
        piece_type: PieceType,
        piece_color: PlayerColor,
        is_lifted: bool,
    ) {
        let idx = index(
            self.viewpoint_color,
            tile,
            piece_type,
            piece_color,
            is_lifted,
        );
        self.push(idx);
    }

    pub fn push_en_passant(&mut self, en_passant: Option<BoardPosition>) {
        if let Some(tile) = en_passant {
            self.push(64 * 24 + viewpoint_tile(self.viewpoint_color, tile).0 as u32);
        } else {
            self.push(self.storage[0]); // Duplicate entry as "None".
        }
    }

    pub(crate) fn push_castling(&mut self, castling: Castling) {
        if self.viewpoint_color == PlayerColor::White {
            self.push_white_castling(castling);
            self.push_black_castling(castling);
        } else {
            self.push_black_castling(castling);
            self.push_white_castling(castling);
        }
    }

    fn push_white_castling(&mut self, castling: Castling) {
        self.push_bool(castling.white_queen_side.is_available());
        self.push_bool(castling.white_king_side.is_available());
    }

    fn push_black_castling(&mut self, castling: Castling) {
        self.push_bool(castling.black_queen_side.is_available());
        self.push_bool(castling.black_king_side.is_available());
    }
}

pub fn index(
    viewpoint_color: PlayerColor,
    tile: BoardPosition,
    piece_type: PieceType,
    piece_color: PlayerColor,
    is_lifted: bool,
) -> u32 {
    let lift_index = u32::from(is_lifted);
    let color_index = if piece_color == viewpoint_color { 0 } else { 1 };
    let piece_index = piece_index(piece_type);
    let viewpoint_tile = viewpoint_tile(viewpoint_color, tile);
    let tile_index = viewpoint_tile.0 as u32;

    tile_index + 64 * (piece_index + 6 * (color_index + 2 * lift_index))
}

pub fn viewpoint_tile(viewpoint_color: PlayerColor, tile: BoardPosition) -> BoardPosition {
    if viewpoint_color == PlayerColor::White {
        tile
    } else {
        vertical_flip(tile)
    }
}

fn piece_index(piece_type: PieceType) -> u32 {
    match piece_type {
        PieceType::Pawn => 0,
        PieceType::Rook => 1,
        PieceType::Knight => 2,
        PieceType::Bishop => 3,
        PieceType::Queen => 4,
        PieceType::King => 5,
    }
}

/// Takes a board position (x, y) and mirrors the y position while keeping the
/// x position the same. This corresponds to switching the viewpoint.
/// We mirror instead of rotating because the King and Queen are not symmetric.
fn vertical_flip(pos: BoardPosition) -> BoardPosition {
    // Field indices are as follows:
    // 56 57 58 59 60 61 62 63
    // 48 49 50 51 52 53 54 55
    // 40 41 42 43 44 45 46 47
    // 32 33 34 35 36 37 38 39
    // 24 25 26 27 28 29 30 31
    // 16 17 18 19 20 21 22 23
    //  8  9 10 11 12 13 14 15
    //  0  1  2  3  4  5  6  7
    BoardPosition::new(pos.x(), 7 - pos.y())
}

#[cfg(test)]
mod tests {
    use crate::{const_tile::pos, PacoAction, PacoError};

    use super::*;

    // Examples verified manually with LibreOffice Calc:
    // scripts/board-representation-index-verification-util.ods

    #[test]
    fn initial_board() {
        let board = DenseBoard::new();
        let mut repr = [0u32; 38];
        index_representation(&board, &mut repr);
        assert_eq!(
            repr,
            [
                64, 129, 194, 259, 324, 197, 134, 71, 8, 9, 10, 11, 12, 13, 14, 15, 432, 433, 434,
                435, 436, 437, 438, 439, 504, 569, 634, 699, 764, 637, 574, 511, 64, 1, 1, 1, 1, 0
            ]
        );

        // Check that the general amount of stuff in the tensor is correct.
        let mut tensor_repr = [0f32; 1920];
        tensor_representation(&board, &mut tensor_repr);
        let tensor_total = tensor_repr.iter().sum::<f32>();
        assert_eq!(tensor_total, 32.0 + 4.0 * 64.0);
    }

    #[test]
    fn lifting_and_en_passant() -> Result<(), PacoError> {
        let mut board = DenseBoard::new();
        board.execute(PacoAction::Lift(pos("e2")))?;
        let mut repr = [0u32; 38];
        index_representation(&board, &mut repr);
        assert_eq!(
            repr,
            [
                64, 129, 194, 259, 324, 197, 134, 71, 8, 9, 10, 11, 13, 14, 15, 432, 433, 434, 435,
                436, 437, 438, 439, 504, 569, 634, 699, 764, 637, 574, 511, 780, 64, 1, 1, 1, 1, 1
            ]
        );
        board.execute(PacoAction::Place(pos("e4")))?;
        index_representation(&board, &mut repr);
        assert_eq!(
            repr,
            [
                504, 569, 634, 699, 764, 637, 574, 511, 432, 433, 434, 435, 437, 438, 439, 420, 8,
                9, 10, 11, 12, 13, 14, 15, 64, 129, 194, 259, 324, 197, 134, 71, 1580, 1, 1, 1, 1,
                1
            ]
        );
        Ok(())
    }

    /// Mirrors an index within the first 25 layers.
    fn mirror_index(index: u32) -> u32 {
        // Apply vertical_flip to index mod 64.
        // Flip bit seven.
        // All other bits are unchanged.
        let pos = index % 64;
        let layer = (index / 64) % 6;
        let color = (index / (64 * 6)) % 2;
        let lift = (index / (64 * 6 * 2)) % 2;
        let tail = index / (64 * 6 * 2 * 2);

        println!("{} {} {} {} {}", pos, layer, color, lift, tail);

        let pos = vertical_flip(BoardPosition(pos as u8)).0 as u32;
        let color = 1 - color;

        println!("{} {} {} {} {}", pos, layer, color, lift, tail);
        println!();

        tail * 64 * 6 * 2 * 2 + lift * 64 * 6 * 2 + color * 64 * 6 + layer * 64 + pos
    }

    #[test]
    #[allow(clippy::needless_range_loop)]
    fn test_correct_mirroring() {
        for _ in 0..100 {
            // Create a random board
            let mut board: DenseBoard = rand::random();
            let mut repr = [0u32; 38];
            index_representation(&board, &mut repr);
            // Mirror the representation in the first 33 indices.
            for i in 0..33 {
                repr[i] = mirror_index(repr[i]);
            }
            // Mirror castling. This switches 33&34 and 35&36.
            repr.swap(33, 35); // Queen side
            repr.swap(34, 36); // King side

            // Change the viewpoint.
            board.controlling_player = board.controlling_player.other();
            let mut repr2 = [0u32; 38];
            index_representation(&board, &mut repr2);

            assert_eq!(repr, repr2);
        }
    }
}
