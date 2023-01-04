//! This module defines all the methods that are exposed in the C library.
//! It is the part that can be used by Julia.

use std::collections::hash_map::DefaultHasher;
use std::str;

use crate::{
    ai::{glue::action_to_action_index, repr::index_representation},
    analysis::{self, reverse_amazon_search},
    determine_all_threats, fen, BoardPosition, DenseBoard, PacoAction, PacoBoard, PlayerColor,
};

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
    println!("{:?}", ps);
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
        crate::VictoryState::RepetitionDraw => 0,
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
            // If julia reserved the wrong amount of space, this could write into
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

/// Returns the index representation of the board state.
/// This is a lot more compressed than the Tensor representation which is very
/// sparse.
///
/// # Safety
///
/// To make this function safe to call, you need to ensure that the out pointer
/// points to a memory block of at least 38 u32. Additionally, you need to ensure
/// that ps points to a valid DenseBoard.
#[no_mangle]
pub unsafe extern "C" fn get_idxrepr(
    ps: *mut DenseBoard,
    out: *mut u32,
    reserved_space: i64,
) -> i64 {
    // Ensure that at least 38 u32 are reserved.
    if reserved_space < 38 {
        return -1;
    }

    let ps: &mut DenseBoard = unsafe { &mut *ps };
    let out: &mut [u32; 38] = unsafe { &mut *(out as *mut [u32; 38]) };

    index_representation(ps, out);

    0 // Everything went fine
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

#[no_mangle]
pub extern "C" fn is_sako_for_other_player(ps: *mut DenseBoard) -> bool {
    let ps: &DenseBoard = unsafe { &*ps };
    analysis::is_sako(ps, ps.controlling_player.other()).unwrap()
}

/// Returns a number between 0 and 64 that counts how many squares are threatened
/// by the current player.
#[no_mangle]
pub extern "C" fn my_threat_count(ps: *mut DenseBoard) -> i64 {
    let ps: &DenseBoard = unsafe { &*ps };
    let threats = determine_all_threats(ps)
        .unwrap()
        .iter()
        .filter(|t| t.0)
        .count() as i64;

    threats
}

/// Finds all the paco sequences that are possible in the given position.
/// Needs to use the output memory to returns these, so it may not return
/// all the chains that were found.
#[no_mangle]
pub extern "C" fn find_paco_sequences(
    ps: *mut DenseBoard,
    out: *mut u8,
    reserved_space: i64,
) -> i64 {
    let ps: &DenseBoard = unsafe { &*ps };

    if !ps.required_action.is_promote() {
        let actions = reverse_amazon_search::find_paco_sequences(ps, ps.controlling_player());
        let Ok(actions) = actions else {
            println!("Error in the reverse amazon search: {:?}", actions);
            println!("Position: {}", crate::fen::write_fen(ps));
            return -1;
        };
        return write_out_chain(actions, ps, reserved_space, out);
    }

    let explored = crate::determine_all_moves(ps.clone());

    let Ok(explored) = explored else {
        return -1;
    };

    let mut actions = vec![];
    // Is there a state where the black king is dancing?
    for board in explored.settled {
        if board.king_in_union(ps.controlling_player.other()) {
            if let Some(trace) = crate::trace_first_move(&board, &explored.found_via) {
                actions.push(trace);
            }
        }
    }

    write_out_chain(actions, ps, reserved_space, out)
}

fn write_out_chain(
    actions: Vec<Vec<PacoAction>>,
    ps: &DenseBoard,
    reserved_space: i64,
    out: *mut u8,
) -> i64 {
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
}

#[no_mangle]
pub extern "C" fn write_fen(ps: *mut DenseBoard, out: *mut u8, reserved_space: i64) -> i64 {
    let ps: &DenseBoard = unsafe { &*ps };

    let fen_string = fen::write_fen(ps);
    let fen_string = fen_string.as_bytes();
    if fen_string.len() as i64 > reserved_space {
        return 0;
    }

    for (i, c) in fen_string.iter().enumerate() {
        unsafe {
            let cell = out.add(i);
            *cell = *c;
        }
    }

    fen_string.len() as i64
}

#[no_mangle]
pub extern "C" fn parse_fen(mut fen_ptr: *mut u8, reserved_space: i64) -> *mut DenseBoard {
    // Read bytes into a buffer vector
    let mut buffer = Vec::with_capacity(reserved_space as usize);
    for _ in 0..reserved_space {
        let byte = unsafe {
            let b = *fen_ptr;
            fen_ptr = fen_ptr.offset(1);
            b
        };
        buffer.push(byte);
    }

    let string_result = str::from_utf8(&buffer);
    match string_result {
        Err(_) => std::ptr::null_mut(),
        Ok(string) => {
            let board = fen::parse_fen(string);
            if let Ok(board) = board {
                leak_to_julia(board)
            } else {
                std::ptr::null_mut()
            }
        }
    }
}
