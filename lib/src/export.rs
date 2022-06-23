//! This module defines all the methods that are exposed in the C library.
//! It is the part that can be used by Julia.

use std::collections::hash_map::DefaultHasher;

use crate::{BoardPosition, DenseBoard, PacoAction, PacoBoard, PieceType, PlayerColor};

#[no_mangle]
pub extern "C" fn new() -> *mut DenseBoard {
    leak_to_julia(DenseBoard::new())
}

/// Leaks the memory (for now) and returns a pointer.
fn leak_to_julia(board: DenseBoard) -> *mut DenseBoard {
    Box::into_raw(Box::from(board))
}

#[no_mangle]
pub extern "C" fn drop(ps: *mut DenseBoard) {
    // Looks like it does not do anything, but should actually deallocate the
    // memory of the PacoSako data structure.
    // Debug only: println!("dropping dense board.");
    let _ = unsafe { Box::from_raw(ps) };
}

#[no_mangle]
pub extern "C" fn print(ps: *mut DenseBoard) {
    let ps: &mut DenseBoard = unsafe { &mut *ps };
    println!("{}", ps);
}

#[no_mangle]
pub extern "C" fn clone(ps: *mut DenseBoard) -> *mut DenseBoard {
    let ps: &mut DenseBoard = unsafe { &mut *ps };
    Box::into_raw(Box::from(ps.clone()))
}

#[no_mangle]
pub extern "C" fn current_player(ps: *mut DenseBoard) -> i64 {
    let ps: &mut DenseBoard = unsafe { &mut *ps };
    match ps.controlling_player() {
        crate::PlayerColor::White => 1,
        crate::PlayerColor::Black => -1,
    }
}

/// Stores a 0 terminated array into the array given by the out pointer. The
/// array must have at least 64 bytes (u8) of space. If all the space is used,
/// no null termination is used.
#[no_mangle]
pub extern "C" fn legal_actions(ps: *mut DenseBoard, mut out: *mut u8) {
    let ps: &mut DenseBoard = unsafe { &mut *ps };
    if let Ok(ls) = ps.actions() {
        let mut length = 0;
        for action in ls {
            let a = action_to_action_index(action.align(ps.controlling_player()));
            unsafe {
                *out = a;
                out = out.offset(1);
                length += 1;
            }
        }
        if length < 64 {
            unsafe { *out = 0 }
        }
    } else {
        unsafe { *out = 0 }
    }
}

fn action_to_action_index(action: crate::PacoAction) -> u8 {
    use crate::PieceType::*;
    match action {
        crate::PacoAction::Lift(p) => 1 + p.0,
        crate::PacoAction::Place(p) => 1 + p.0 + 64,
        crate::PacoAction::Promote(Rook) => 129,
        crate::PacoAction::Promote(Knight) => 130,
        crate::PacoAction::Promote(Bishop) => 131,
        crate::PacoAction::Promote(Queen) => 132,
        crate::PacoAction::Promote(_) => 255,
    }
}

trait PlayerAlign {
    /// If the given player is Black, then the position is flipped around.
    /// Applying this twice must return the original value.
    fn align(self, color: PlayerColor) -> Self;
}

impl PlayerAlign for BoardPosition {
    fn align(self, color: PlayerColor) -> Self {
        if color == PlayerColor::White {
            self
        } else {
            mirror_paco_position(self)
        }
    }
}

impl PlayerAlign for PacoAction {
    fn align(self, color: PlayerColor) -> Self {
        match self {
            PacoAction::Lift(p) => PacoAction::Lift(p.align(color)),
            PacoAction::Place(p) => PacoAction::Place(p.align(color)),
            PacoAction::Promote(_) => self,
        }
    }
}

#[no_mangle]
pub extern "C" fn apply_action_bang(ps: *mut DenseBoard, action: u8) -> i64 {
    use crate::PieceType::*;
    let ps: &mut DenseBoard = unsafe { &mut *ps };

    let action = if (1..=64).contains(&action) {
        crate::PacoAction::Lift(BoardPosition(action - 1))
    } else if action <= 128 {
        crate::PacoAction::Place(BoardPosition(action - 1 - 64))
    } else if action == 129 {
        crate::PacoAction::Promote(Rook)
    } else if action == 130 {
        crate::PacoAction::Promote(Knight)
    } else if action == 131 {
        crate::PacoAction::Promote(Bishop)
    } else if action == 132 {
        crate::PacoAction::Promote(Queen)
    } else {
        return -1;
    };
    let res = ps.execute(action.align(ps.controlling_player()));
    if res.is_err() {
        -1
    } else {
        0
    }
}

#[no_mangle]
pub extern "C" fn status(ps: *mut DenseBoard) -> i64 {
    use crate::PlayerColor::*;
    let ps: &mut DenseBoard = unsafe { &mut *ps };
    match ps.victory_state {
        crate::VictoryState::Running => 42,
        crate::VictoryState::PacoVictory(White) => 1,
        crate::VictoryState::PacoVictory(Black) => -1,
        crate::VictoryState::TimeoutVictory(White) => 1,
        crate::VictoryState::TimeoutVictory(Black) => -1,
        crate::VictoryState::NoProgressDraw => 0,
    }
}

////////////////////////////////////////////////////////////////////////////////
// (De-)Serialization //////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

#[no_mangle]
pub extern "C" fn serialize_len(ps: *mut DenseBoard) -> i64 {
    let ps: &mut DenseBoard = unsafe { &mut *ps };

    if let Ok(encoded) = bincode::serialize(ps) {
        encoded.len() as i64
    } else {
        -1
    }
}

/// Expects an out pointer to an u8 array that has exactly serialize_len(ps)
/// space to store the board. This means we are currently doing serialization
/// twice to avoid having to allocate a julia array from rust code.
///
/// If you improperly specify the buffer, this may buffer overrun and cause a
/// security issue. Make sure you own the memory you write to!
#[no_mangle]
pub extern "C" fn serialize(ps: *mut DenseBoard, mut out: *mut u8, reserved_space: i64) -> i64 {
    let ps: &mut DenseBoard = unsafe { &mut *ps };

    if let Ok(encoded) = bincode::serialize(ps) {
        if encoded.len() as i64 != reserved_space {
            // If julia reserved the wrong amout of space, this could write into
            // memory it is not supposed to, triggering a Segfault in the best
            // case and a vulnerability in the worst case. This is why we double
            // check the reserved space.
            return -1;
        }
        for byte in encoded {
            unsafe {
                *out = byte;
                out = out.offset(1);
            }
        }
        0 // No error :-)
    } else {
        -2
    }
}

/// Tries to deserialize a DenseBoard from the given bincode data. If the
/// conversion fails this will return a null pointer.
///
/// If you don't properly specify the buffer size, this can buffer over-read and
/// copy memory you may not want exposed to a new location.
/// (e.g. Heartblead was a buffer over-read vulnerability)
/// Make sure you own the memory you read from!
#[no_mangle]
pub extern "C" fn deserialize(mut bincode_ptr: *mut u8, reserved_space: i64) -> *mut DenseBoard {
    // Read bytes into a buffer vector
    let mut buffer = Vec::with_capacity(reserved_space as usize);
    for _ in 0..reserved_space {
        let byte = unsafe {
            let b = *bincode_ptr;
            bincode_ptr = bincode_ptr.offset(1);
            b
        };
        buffer.push(byte);
    }

    let board: Result<DenseBoard, _> = bincode::deserialize(&buffer);
    if let Ok(board) = board {
        leak_to_julia(board)
    } else {
        std::ptr::null_mut()
    }
}

/// Layers are:
/// (Pawn, Rook, Knight, Bishop, Queen, King) x (White, Black) x (settled, lifted) # 24
/// Single layers for flags, 4xCastling + en passant + no-progress # 6
#[no_mangle]
pub extern "C" fn repr_layer_count() -> i64 {
    24 + 6
}

/// Generates a Tensor representation of the board state for machine learning.
/// When the black player is playing, the white and black pieces are flipped.
/// Both the memory blocks are switched and the top/bottom is switched.
/// This means the AI does not really know which color it is playing.
#[no_mangle]
pub extern "C" fn repr(ps: *mut DenseBoard, out: *mut f32, reserved_space: i64) -> i64 {
    let ps: &mut DenseBoard = unsafe { &mut *ps };
    if reserved_space != repr_layer_count() * 8 * 8 {
        return -1;
    }

    // How does this vector look representing the Tensor?
    // (1 3) (5 7)
    // (2 4) (6 8)
    // -> 1 2 3 4 5 6 7 8

    // Layers describing the settled pieces
    let white_offset = color_offset(PlayerColor::White, ps.controlling_player()) as isize;
    let black_offset = color_offset(PlayerColor::Black, ps.controlling_player()) as isize;
    for t in 0..64 {
        let mirror_t = if ps.controlling_player() == PlayerColor::White {
            t
        } else {
            mirror_paco_position(BoardPosition(t as u8)).0 as isize
        };
        if let Some(&Some(piece_type)) = ps.white.get(t as usize) {
            unsafe {
                let cell = out.offset(mirror_t + 64 * layer_offset(piece_type) + white_offset);
                *cell = 1.0;
            }
        }
        if let Some(&Some(piece_type)) = ps.black.get(t as usize) {
            unsafe {
                let cell = out.offset(mirror_t + 64 * layer_offset(piece_type) + black_offset);
                *cell = 1.0;
            }
        }
    }

    // Layers describing the lifted pieces
    match ps.lifted_piece {
        crate::Hand::Empty => {}
        crate::Hand::Single { piece, position } => unsafe {
            enable_cell_at(position, piece, true, true, out);
        },
        crate::Hand::Pair {
            piece,
            partner,
            position,
        } => unsafe {
            enable_cell_at(position, piece, true, true, out);
            enable_cell_at(position, partner, false, true, out);
        },
    }

    // Flag layers describing castling options
    if ps.controlling_player() == PlayerColor::White {
        if ps.castling.white_queen_side {
            unsafe { set_layer(24, 1.0, out) };
        }
        if ps.castling.white_king_side {
            unsafe { set_layer(25, 1.0, out) };
        }
        if ps.castling.black_queen_side {
            unsafe { set_layer(26, 1.0, out) };
        }
        if ps.castling.black_king_side {
            unsafe { set_layer(27, 1.0, out) };
        }
    } else {
        if ps.castling.black_queen_side {
            unsafe { set_layer(24, 1.0, out) };
        }
        if ps.castling.black_king_side {
            unsafe { set_layer(25, 1.0, out) };
        }
        if ps.castling.white_queen_side {
            unsafe { set_layer(26, 1.0, out) };
        }
        if ps.castling.white_king_side {
            unsafe { set_layer(27, 1.0, out) };
        }
    }

    // Layer that shows the en-passant square
    if let Some((t, c)) = ps.en_passant {
        if c != ps.controlling_player() {
            let mirror_t = if ps.controlling_player() == PlayerColor::White {
                t.0 as isize
            } else {
                mirror_paco_position(BoardPosition(t.0 as u8)).0 as isize
            };
            unsafe {
                let cell = out.offset(mirror_t + 64 * 28);
                *cell = 1.0
            }
        }
    }

    // Layer that gives the half-move counter (normalized between 0 and 1)
    unsafe { set_layer(29, ps.no_progress_half_moves as f32 / 100.0, out) }

    // Still missing are the "repetition" layers. Doing the same move 3 times
    // leads to a draw. This is not implemented in the engine yet.

    0
}

unsafe fn set_layer(layer: isize, value: f32, out: *mut f32) {
    for i in 0..64 {
        let cell = out.offset(64 * layer + i);
        *cell = value;
    }
}

unsafe fn enable_cell_at(
    pos: BoardPosition,
    piece_type: PieceType,
    is_for_current_player: bool,
    is_lifted: bool,
    out: *mut f32,
) {
    let color_offset = if is_for_current_player { 0 } else { 6 * 64 };
    let lift_offset = if is_lifted { 12 * 64 } else { 0 };
    let pos = if is_for_current_player {
        pos.0 as isize
    } else {
        mirror_paco_position(pos).0 as isize
    };
    let offset = pos + layer_offset(piece_type) + color_offset + lift_offset;

    let cell = out.offset(offset);
    *cell = 1.0;
}

fn color_offset(color: PlayerColor, controlling_player: PlayerColor) -> i32 {
    if color == controlling_player {
        0
    } else {
        6 * 64
    }
}

fn mirror_paco_position(pos: BoardPosition) -> BoardPosition {
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

fn layer_offset(piece_type: PieceType) -> isize {
    match piece_type {
        PieceType::Pawn => 0,
        PieceType::Rook => 1,
        PieceType::Knight => 2,
        PieceType::Bishop => 3,
        PieceType::Queen => 4,
        PieceType::King => 5,
    }
}

#[no_mangle]
pub extern "C" fn equals(ps1: *mut DenseBoard, ps2: *mut DenseBoard) -> i64 {
    let ps1: &DenseBoard = unsafe { &*ps1 };
    let ps2: &DenseBoard = unsafe { &*ps2 };

    if ps1 == ps2 {
        0
    } else {
        1
    }
}

#[no_mangle]
pub extern "C" fn hash(ps: *mut DenseBoard) -> u64 {
    use std::hash::{Hash, Hasher};
    let ps: &DenseBoard = unsafe { &*ps };
    let mut hasher = DefaultHasher::new();
    ps.hash(&mut hasher);
    hasher.finish()
}

#[no_mangle]
pub extern "C" fn random_position() -> *mut DenseBoard {
    use rand::Rng;

    let mut rng = rand::thread_rng();
    let board: DenseBoard = rng.gen();
    leak_to_julia(board)
}

// status_code = ccall((:find_sako_sequences, DYNLIB_PATH), Int64,
// (Ptr{Nothing}, Ptr{UInt8}, Int64),
// ps.ptr, memory, memory_length)

/// Finds all the sako sequences that are possible in the given position.
/// Needs to use the output memory to returns these, so it may not return
/// all the chains that were found.
#[no_mangle]
pub extern "C" fn find_sako_sequences(
    ps: *mut DenseBoard,
    out: *mut u8,
    reserved_space: i64,
) -> i64 {
    let ps: &DenseBoard = unsafe { &*ps };

    let explored = crate::determine_all_moves(ps.clone());
    if let Ok(explored) = explored {
        let mut actions = vec![];
        // Is there a state where the black king is dancing?
        for board in explored.settled {
            if board.king_in_union(ps.current_player.other()) {
                if let Some(trace) = crate::trace_first_move(&board, &explored.found_via) {
                    actions.push(trace);
                }
            }
        }

        // Now we have generated a list of chains and can write this into a null
        // separated list.
        let mut offset = 0;
        for chain in actions {
            // Check if the whole action fits in the remaining memory.
            let remaining_memory = reserved_space - offset;
            if remaining_memory < chain.len() as i64 {
                return 0;
            }
            for action in chain {
                let a = action_to_action_index(action.align(ps.controlling_player()));
                unsafe {
                    let cell = out.offset(offset as isize);
                    *cell = a;
                }
                offset += 1;
            }
            // Leave a space unwritten to terminate the chain.
            // This is optional and does not need to be written for the last
            // chain if there is no more space for this one byte.
            offset += 1;
            if reserved_space - offset > 0 {
                unsafe {
                    let cell = out.offset(offset as isize);
                    *cell = 0;
                }
            }
        }

        0
    } else {
        -1
    }
}
