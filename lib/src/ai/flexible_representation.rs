//! Originally, there was only one way to represent the game state for consumption
//! by the AI. This module provides a more flexible way to represent the game
//! where you can pass in options to customize the representation.
//!
//! To make it easy to construct them in Julia and Consume them in Rust, we
//! store it as flags on an u32 integer.

use crate::{
    castling::Castling, substrate::Substrate, BoardPosition, DenseBoard, PacoBoard, PieceType,
    PlayerColor, RequiredAction,
};

use super::repr;

/// `USE_RELATIVE_PERSPECTIVE = 1` means that the AI will see the board from the
/// perspective of the player to move.
/// `USE_RELATIVE_PERSPECTIVE = 0` means that the AI will see the board
/// from the perspective of white.
/// This CHANGES how layers are represented.
/// This also adds a layer to indicate the active player.
const USE_RELATIVE_PERSPECTIVE: u32 = 1 << 0;

/// Is Settled = 1 enables an ADDITIONAL layer. This layer is the same everywhere
/// 1 => You need to lift a piece now; 0 => You place or promote.
const WITH_MUST_LIFT: u32 = 1 << 1;

/// Must Promote = 1 enables an ADDITIONAL layer. This layer is the same everywhere
/// 1 => You need to promote a piece now; 0 => You lift or place
const WITH_MUST_PROMOTE: u32 = 1 << 2;

/// Errors that may occur while building a representation:
#[derive(Debug, thiserror::Error)]
pub enum RepresentationError {
    #[error("Too many indices. The maximum is {0}.")]
    TooManyIndices(usize),
    #[error("No index at all. There must be at least one!")]
    NoIndices,
    #[error("The representation options are invalid.")]
    InvalidRepresentationOptions,
}

#[derive(Debug, Copy, Clone)]
pub struct FlexibleRepresentationOptions(u32);

impl FlexibleRepresentationOptions {
    pub fn new(opts: u32) -> Result<Self, RepresentationError> {
        if opts & !0b111 != 0 {
            return Err(RepresentationError::InvalidRepresentationOptions);
        }
        Ok(Self(opts))
    }

    pub fn set_use_relative_perspective(&mut self, value: bool) {
        if value {
            self.0 |= USE_RELATIVE_PERSPECTIVE;
        } else {
            self.0 &= !USE_RELATIVE_PERSPECTIVE;
        }
    }

    pub fn set_with_must_lift(&mut self, value: bool) {
        if value {
            self.0 |= WITH_MUST_LIFT;
        } else {
            self.0 &= !WITH_MUST_LIFT;
        }
    }

    pub fn set_with_must_promote(&mut self, value: bool) {
        if value {
            self.0 |= WITH_MUST_PROMOTE;
        } else {
            self.0 &= !WITH_MUST_PROMOTE;
        }
    }

    pub fn use_relative_perspective(&self) -> bool {
        self.0 & USE_RELATIVE_PERSPECTIVE != 0
    }

    pub fn must_lift(&self) -> bool {
        self.0 & WITH_MUST_LIFT != 0
    }

    pub fn must_promote(&self) -> bool {
        self.0 & WITH_MUST_PROMOTE != 0
    }

    pub fn index_representation(
        &self,
        board: &DenseBoard,
    ) -> Result<IndexRepresentation, RepresentationError> {
        index_representation(board, *self)
    }
}

impl Default for FlexibleRepresentationOptions {
    fn default() -> Self {
        Self(USE_RELATIVE_PERSPECTIVE)
    }
}

impl FlexibleRepresentationOptions {
    pub fn layer_count(&self) -> usize {
        let mut count = INDEX_REPRESENTATION_LAYER_COUNT;
        count += 1; // En passant square
        count += 4; // Castling rights
        if !self.use_relative_perspective() {
            count += 1; // Active player
        }
        if self.must_lift() {
            count += 1; // Must lift
        }
        if self.must_promote() {
            count += 1; // Must promote
        }
        count += 1; // Half move clock
        count
    }

    pub fn index_representation_length(&self) -> usize {
        let mut length = PIECE_COUNT;
        length += 1; // En passant square
        length += 4; // Castling rights
        if !self.use_relative_perspective() {
            length += 1; // Active player
        }
        if self.must_lift() {
            length += 1; // Must lift
        }
        if self.must_promote() {
            length += 1; // Must promote
        }
        length += 1; // Half move clock
        length
    }
}

/// "With Opts" version of repr_layer_count.
// SAFETY: there is no other global function of this name.
#[unsafe(no_mangle)]
pub extern "C" fn repr_layer_count_opts(opts: u32) -> i64 {
    let Ok(options) = FlexibleRepresentationOptions::new(opts) else {
        return -1;
    };
    options.layer_count() as i64
}

/// There are (piece types) * colors * (lifted/placed) = 6 * 2 * 2 = 24 layers
/// for the piece position tensor.
const INDEX_REPRESENTATION_LAYER_COUNT: usize = 24;

/// There are 32 pieces on the board at all times.
const PIECE_COUNT: usize = 32;

/// Dynamically sized index representation. The actual size depends on the flags
/// being passed in.
#[derive(Debug, Clone)]
pub struct IndexRepresentation {
    // Which options was/am I constructed with?
    options: FlexibleRepresentationOptions,
    // Who is the controlling player?
    perspective: PlayerColor,
    // The tensor representation starts with many layers forming a sparse tensor.
    // This contains
    //  - All pieces with type, color and "liftedness". => 32 indices
    // Additional layers:
    //  - En passant square (if any) - Always on.
    sparse_tensor_indices: Vec<u32>, // Should have 32 or 33 indices.

    // Then there is some information that we want to communicate all over the board.
    // Castling rights:
    // (Queen 1, King 1, Queen 2, King 2) - Affected by perspective! - Always on.
    // And some optional layers:
    //  - Active Player (0 => White, 1 => Black) - Only without perspective
    //  - Must Lift
    //  - Must Promote
    boolean_layers: Vec<u32>,

    // Layers where and idx-repr of 0u32 - 100u32 is interpolated into 0.0f32 - 1.0f32
    percentage_layers: Vec<u32>,
}

impl IndexRepresentation {
    fn new(options: FlexibleRepresentationOptions, perspective: PlayerColor) -> Self {
        Self {
            options,
            perspective,
            sparse_tensor_indices: Vec::with_capacity(33),
            boolean_layers: Vec::with_capacity(7),
            percentage_layers: Vec::with_capacity(1),
        }
    }

    /// Any localized entry into the tensor representation must know whether we
    /// are using the "perspective of current layer" or "white perspective".
    fn used_perspective(&self) -> PlayerColor {
        if self.options.use_relative_perspective() {
            self.perspective
        } else {
            PlayerColor::White
        }
    }

    /// Add an index to the representation.
    fn push_index(
        &mut self,
        tile: BoardPosition,
        piece_type: PieceType,
        piece_color: PlayerColor,
        is_lifted: bool,
    ) {
        let index = repr::index(
            self.used_perspective(),
            tile,
            piece_type,
            piece_color,
            is_lifted,
        );
        self.sparse_tensor_indices.push(index);
    }

    /// If there is an en passant square, then we add it to the representation.
    /// Otherwise, we take an existing index from the sparse tensor.
    /// Duplicating an existing index does nothing to the tensor representation.
    fn push_en_passant_square(
        &mut self,
        en_passant: Option<BoardPosition>,
    ) -> Result<(), RepresentationError> {
        let index: u32 = if let Some(tile) = en_passant {
            64 * INDEX_REPRESENTATION_LAYER_COUNT as u32
                + repr::viewpoint_tile(self.used_perspective(), tile).0 as u32
        } else if self.sparse_tensor_indices.is_empty() {
            return Err(RepresentationError::NoIndices);
        } else {
            self.sparse_tensor_indices[0]
        };
        self.sparse_tensor_indices.push(index);
        Ok(())
    }

    /// Adds four layers for castling rights. Values are 0 or 1.
    /// This assumes standard position, no Fischer randomization.
    fn push_castling(&mut self, castling: Castling) {
        if self.used_perspective() == PlayerColor::White {
            self.boolean_layers
                .push(castling.white_queen_side.is_available() as u32);
            self.boolean_layers
                .push(castling.white_king_side.is_available() as u32);
            self.boolean_layers
                .push(castling.black_queen_side.is_available() as u32);
            self.boolean_layers
                .push(castling.black_king_side.is_available() as u32);
        } else {
            self.boolean_layers
                .push(castling.black_queen_side.is_available() as u32);
            self.boolean_layers
                .push(castling.black_king_side.is_available() as u32);
            self.boolean_layers
                .push(castling.white_queen_side.is_available() as u32);
            self.boolean_layers
                .push(castling.white_king_side.is_available() as u32);
        }
    }

    /// When use_relative_perspective is off, then we need to communicate the AI which
    /// side it actually controls. This is done by conditionally adding a single layer.
    fn push_perspective(&mut self) {
        if !self.options.use_relative_perspective() {
            self.boolean_layers.push(self.perspective as u32);
        }
    }

    /// Writes the representation to a pre-allocated buffer.
    pub fn write_to(&self, new_repr: &mut [u32]) {
        let new_repr_len = new_repr.len();
        assert_eq!(new_repr_len, self.options.index_representation_length());
        // Copy self.sparse_tensor_indices to the beginning of the buffer.
        new_repr[..self.sparse_tensor_indices.len()].copy_from_slice(&self.sparse_tensor_indices);
        // Copy self.boolean_layers to the middle of the buffer.
        new_repr[self.sparse_tensor_indices.len()
            ..self.sparse_tensor_indices.len() + self.boolean_layers.len()]
            .copy_from_slice(&self.boolean_layers);
        // Copy self.percentage_layers to the end of the buffer.
        new_repr[new_repr_len - self.percentage_layers.len()..]
            .copy_from_slice(&self.percentage_layers);
    }

    pub fn write_vec(&self) -> Vec<u32> {
        let mut new_repr = vec![0u32; self.options.index_representation_length()];
        self.write_to(&mut new_repr);
        new_repr
    }
}

pub fn index_representation(
    board: &DenseBoard,
    options: FlexibleRepresentationOptions,
) -> Result<IndexRepresentation, RepresentationError> {
    let mut repr = IndexRepresentation::new(options, board.controlling_player());

    // Pieces that are settled on the board. This should be between 30 and 32.
    for piece_color in PlayerColor::all() {
        for tile in BoardPosition::all() {
            if let Some(piece_type) = board.substrate.get_piece(piece_color, tile) {
                repr.push_index(tile, piece_type, piece_color, false);
            }
        }
    }
    assert!(repr.sparse_tensor_indices.len() <= PIECE_COUNT);
    assert!(repr.sparse_tensor_indices.len() >= PIECE_COUNT - 2);

    // Pieces that are currently lifted. Afterwards there are always 32 pieces.
    match board.lifted_piece {
        crate::Hand::Empty => {}
        crate::Hand::Single { piece, position } => {
            repr.push_index(position, piece, board.controlling_player(), true);
        }
        crate::Hand::Pair {
            piece,
            partner,
            position,
        } => {
            repr.push_index(position, piece, board.controlling_player(), true);
            repr.push_index(position, partner, board.controlling_player().other(), true);
        }
    }
    assert_eq!(repr.sparse_tensor_indices.len(), PIECE_COUNT);

    // En passant square.
    repr.push_en_passant_square(board.en_passant)?;

    // Castling rights.
    repr.push_castling(board.castling);

    // Perspective.
    repr.push_perspective();

    // Must lift & Must promote.
    let (must_lift, must_promote) = match board.required_action {
        RequiredAction::PromoteThenLift => (1, 1),
        RequiredAction::Lift => (1, 0),
        RequiredAction::Place => (0, 0),
        RequiredAction::PromoteThenPlace => (0, 1),
        RequiredAction::PromoteThenFinish => (0, 1),
    };

    if repr.options.must_lift() {
        repr.boolean_layers.push(must_lift);
    }
    if repr.options.must_promote() {
        repr.boolean_layers.push(must_promote);
    }

    // Half move clock.
    repr.percentage_layers
        .push(board.draw_state.no_progress_half_moves as u32);

    Ok(repr)
}

#[cfg(test)]
mod test {
    use crate::const_tile::*;
    use crate::PacoAction;

    use super::*;

    /// Verifies that the initial board is represented correctly. This tests
    /// various options.
    #[test]
    fn initial_board() -> Result<(), Box<dyn std::error::Error>> {
        let board = DenseBoard::new();

        assert_eq!(
            index_representation(&board, FlexibleRepresentationOptions::default())?.write_vec(),
            vec![
                64, 129, 194, 259, 324, 197, 134, 71, 8, 9, 10, 11, 12, 13, 14, 15, 432, 433, 434,
                435, 436, 437, 438, 439, 504, 569, 634, 699, 764, 637, 574, 511, 64, 1, 1, 1, 1, 0,
            ]
        );

        let mut opts = FlexibleRepresentationOptions::default();
        opts.set_use_relative_perspective(false);
        opts.set_with_must_lift(true);
        opts.set_with_must_promote(true);

        assert_eq!(
            index_representation(&board, opts)?.write_vec(),
            vec![
                64, 129, 194, 259, 324, 197, 134, 71, 8, 9, 10, 11, 12, 13, 14, 15, 432, 433, 434,
                435, 436, 437, 438, 439, 504, 569, 634, 699, 764, 637, 574, 511, 64, 1, 1, 1, 1, 0,
                1, 0, 0,
            ]
        );

        Ok(())
    }

    #[test]
    fn after_one_move() -> Result<(), Box<dyn std::error::Error>> {
        let mut board = DenseBoard::new();
        board.execute(PacoAction::Lift(C2))?;
        board.execute(PacoAction::Place(C4))?;

        let mut opts = FlexibleRepresentationOptions::default();
        opts.set_use_relative_perspective(false);
        opts.set_with_must_lift(true);
        opts.set_with_must_promote(true);

        let representation = index_representation(&board, opts)?;
        let player = representation.boolean_layers[4];
        assert_eq!(player, 1);
        assert_eq!(
            representation.write_vec(),
            vec![
                64, 129, 194, 259, 324, 197, 134, 71, 8, 9, 11, 12, 13, 14, 15, 26, 432, 433, 434,
                435, 436, 437, 438, 439, 504, 569, 634, 699, 764, 637, 574, 511, 1554, 1, 1, 1, 1,
                1, 1, 0, 1,
            ]
        );

        Ok(())
    }

    #[test]
    fn regression_test() -> Result<(), Box<dyn std::error::Error>> {
        // Generates random positions, compares with the old representation.
        // Will execute 0-3 legal actions to capture more positions.

        for _ in 0..1000 {
            let mut board: DenseBoard = rand::random();
            let action_count = rand::random::<u8>() % 4;
            for _ in 0..action_count {
                let actions = board.actions()?;
                if actions.is_empty() {
                    break;
                }
                let actions: Vec<_> = actions.into_iter().collect();
                let action_count = actions.len();
                let action = actions[rand::random::<usize>() % action_count];
                board.execute(action)?;
            }

            let options = FlexibleRepresentationOptions::default();
            let mut old_repr = [0u32; 38];
            repr::index_representation(&board, &mut old_repr);
            let new_index_repr = index_representation(&board, options)?;
            let mut new_repr = [0u32; 38];
            new_index_repr.write_to(&mut new_repr);

            assert_eq!(old_repr, new_repr);
        }

        Ok(())
    }

    #[test]
    #[allow(clippy::bool_assert_comparison)]
    fn test_flexible_representation_options() {
        let mut options = FlexibleRepresentationOptions::default();
        assert_eq!(options.use_relative_perspective(), true);
        assert_eq!(options.must_lift(), false);
        assert_eq!(options.must_promote(), false);
        assert_eq!(options.layer_count(), 30);
        assert_eq!(options.index_representation_length(), 38);

        options.set_use_relative_perspective(false);
        assert_eq!(options.use_relative_perspective(), false);
        assert_eq!(options.must_lift(), false);
        assert_eq!(options.must_promote(), false);
        assert_eq!(options.layer_count(), 31);
        assert_eq!(options.index_representation_length(), 39);

        options.set_with_must_lift(true);
        assert_eq!(options.use_relative_perspective(), false);
        assert_eq!(options.must_lift(), true);
        assert_eq!(options.must_promote(), false);
        assert_eq!(options.layer_count(), 32);
        assert_eq!(options.index_representation_length(), 40);

        options.set_with_must_promote(true);
        assert_eq!(options.use_relative_perspective(), false);
        assert_eq!(options.must_lift(), true);
        assert_eq!(options.must_promote(), true);
        assert_eq!(options.layer_count(), 33);
        assert_eq!(options.index_representation_length(), 41);

        options.set_use_relative_perspective(true);
        assert_eq!(options.use_relative_perspective(), true);
        assert_eq!(options.must_lift(), true);
        assert_eq!(options.must_promote(), true);
        assert_eq!(options.layer_count(), 32);
        assert_eq!(options.index_representation_length(), 40);

        options.set_with_must_lift(false);
        assert_eq!(options.use_relative_perspective(), true);
        assert_eq!(options.must_lift(), false);
        assert_eq!(options.must_promote(), true);
        assert_eq!(options.layer_count(), 31);
        assert_eq!(options.index_representation_length(), 39);

        options.set_with_must_promote(false);
        assert_eq!(options.use_relative_perspective(), true);
        assert_eq!(options.must_lift(), false);
        assert_eq!(options.must_promote(), false);
        assert_eq!(options.layer_count(), 30);
        assert_eq!(options.index_representation_length(), 38);
    }
}
