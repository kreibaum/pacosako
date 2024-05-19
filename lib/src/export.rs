//! This module defines all the methods that are exposed in the C library.
//! It is the part that can be used by Julia.

use fxhash::FxHasher;
use std::str;

use crate::{
    ai::{
        flexible_representation::FlexibleRepresentationOptions,
        glue::{action_index_to_action, action_to_action_index},
        repr::index_representation,
    },
    analysis::{self, reverse_amazon_search},
    determine_all_threats, fen,
    setup_options::SetupOptions,
    BoardPosition, DenseBoard, PacoAction, PacoBoard,
    PieceType::*,
    PlayerColor, VictoryState,
};

#[no_mangle]
pub extern "C" fn new() -> *mut DenseBoard {
    leak_to_julia(DenseBoard::with_options(&SetupOptions {
        draw_after_n_repetitions: 3,
        ..Default::default()
    }))
}

/// Leaks the memory (for now) and returns a pointer.
///
/// Leaking memory is safe, so no unsafe annotation here.
fn leak_to_julia(board: DenseBoard) -> *mut DenseBoard {
    Box::into_raw(Box::from(board))
}

/// This function drops the memory of the given DenseBoard.
///
/// # Safety
///
/// To make this function safe to call, you need to make sure that the pointer
/// is valid and that the memory is not used anymore.
#[no_mangle]
pub unsafe extern "C" fn drop(ps: *mut DenseBoard) {
    // Looks like it does not do anything, but should actually deallocate the
    // memory of the PacoSako data structure.
    // Debug only: println!("dropping dense board.");
    let _ = unsafe { Box::from_raw(ps) };
}

/// This function prints the given DenseBoard.
///
/// # Safety
///
/// The ps pointer must be valid.
#[no_mangle]
pub unsafe extern "C" fn print(ps: *mut DenseBoard) {
    let ps: &mut DenseBoard = unsafe { &mut *ps };
    println!("{:?}", ps);
}

/// Clones a DenseBoard and returns the pointer to the clone.
/// The original DenseBoard is not touched.
///
/// # Safety
///
/// The ps pointer must be valid.
#[no_mangle]
pub unsafe extern "C" fn clone(ps: *mut DenseBoard) -> *mut DenseBoard {
    let ps: &mut DenseBoard = unsafe { &mut *ps };
    Box::into_raw(Box::from(ps.clone()))
}

/// This function returns the current player.
/// 1 for white, -1 for black.
///
/// # Safety
///
/// The ps pointer must be valid.
#[no_mangle]
pub unsafe extern "C" fn current_player(ps: *mut DenseBoard) -> i64 {
    let ps: &mut DenseBoard = unsafe { &mut *ps };
    match ps.controlling_player() {
        crate::PlayerColor::White => 1,
        crate::PlayerColor::Black => -1,
    }
}

/// Writes a label for the action as a utf8 string into the given buffer.
/// The buffer should have two byes of space. The length of the string is
/// returned. If the buffer is too small, 0 is returned.
///
/// # Safety
///
/// The ps pointer must be valid. The out pointer must be valid and the
/// reserved_space must really be available.
#[no_mangle]
pub unsafe extern "C" fn movelabel(
    ps: *mut DenseBoard,
    action: u8,
    out: *mut u8,
    reserved_space: i64,
) -> i64 {
    let ps: &mut DenseBoard = unsafe { &mut *ps };

    let Some(action) = action_index_to_action(action) else {
        return -1;
    };

    let action = action.align(ps.controlling_player());
    let label = match action {
        PacoAction::Lift(p) => format!("{}", p),
        PacoAction::Place(p) => format!("{}", p),
        PacoAction::Promote(Queen) => "=Q".to_string(),
        PacoAction::Promote(Rook) => "=R".to_string(),
        PacoAction::Promote(Bishop) => "=B".to_string(),
        PacoAction::Promote(Knight) => "=N".to_string(),
        _ => "??".to_string(),
    };

    write_byte_string(&label, out, reserved_space)
}

/// Stores a 0 terminated array into the array given by the out pointer. The
/// array must have at least 64 bytes (u8) of space. If all the space is used,
/// no null termination is used.
///
/// # Safety
///
/// The ps pointer must be valid. The out pointer must be valid and have at
/// least 64 bytes of space.
#[no_mangle]
pub unsafe extern "C" fn legal_actions(ps: *mut DenseBoard, mut out: *mut u8) {
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

/// Executes the given action. Returns 0 if the action was successful, -1
/// otherwise.
///
/// # Safety
///
/// The pointer must point to a valid DenseBoard. The action does not have to be
/// a legal action nor does it have to be a valid action.
#[no_mangle]
pub unsafe extern "C" fn apply_action_bang(ps: *mut DenseBoard, action: u8) -> i64 {
    let ps: &mut DenseBoard = unsafe { &mut *ps };

    let Some(action) = action_index_to_action(action) else {
        return -1;
    };

    let res = ps.execute(action.align(ps.controlling_player()));
    if res.is_err() {
        -1
    } else {
        0
    }
}

/// Returns the victory state of the game, reduced to a single number.
/// 1 for white victory, -1 for black victory, 0 for draw, 42 for running.
///
/// # Safety
///
/// The pointer must point to a valid DenseBoard.
#[no_mangle]
pub unsafe extern "C" fn status(ps: *mut DenseBoard) -> i64 {
    use crate::PlayerColor::*;
    let ps: &mut DenseBoard = unsafe { &mut *ps };
    match ps.victory_state {
        VictoryState::Running => 42,
        VictoryState::PacoVictory(White) => 1,
        VictoryState::PacoVictory(Black) => -1,
        VictoryState::TimeoutVictory(White) => 1,
        VictoryState::TimeoutVictory(Black) => -1,
        VictoryState::NoProgressDraw => 0,
        VictoryState::RepetitionDraw => 0,
    }
}

/// Returns the half move count of the game.
///
/// # Safety
///
/// The pointer must point to a valid DenseBoard.
#[no_mangle]
pub unsafe extern "C" fn half_move_count(ps: *mut DenseBoard) -> i64 {
    let ps: &mut DenseBoard = unsafe { &mut *ps };
    ps.half_move_count as i64
}

/// Returns the full move count of the game.
///
/// # Safety
///
/// The pointer must point to a valid DenseBoard.
#[no_mangle]
pub unsafe extern "C" fn move_count(ps: *mut DenseBoard) -> i64 {
    let ps: &mut DenseBoard = unsafe { &mut *ps };
    ps.move_count as i64
}

/// Returns the number of actions that have been executed in the game.
///
/// # Safety
///
/// The pointer must point to a valid DenseBoard.
#[no_mangle]
pub unsafe extern "C" fn action_count(ps: *mut DenseBoard) -> i64 {
    let ps: &mut DenseBoard = unsafe { &mut *ps };
    ps.action_count as i64
}

////////////////////////////////////////////////////////////////////////////////
// (De-)Serialization //////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

/// Returns the length of the serialized board. Returns -1 if the serialization
/// failed. This is required to allocate the correct amount of memory in julia.
///
/// # Safety
///
/// The pointer must point to a valid DenseBoard.
#[no_mangle]
pub unsafe extern "C" fn serialize_len(ps: *mut DenseBoard) -> i64 {
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
///
/// Returns -1 if the serialization failed.
///
///
/// # Safety
///
/// The out pointer must point to a valid u8 array with at least serialize_len(ps)
/// bytes of space. The ps pointer must point to a valid DenseBoard.
#[no_mangle]
pub unsafe extern "C" fn serialize(
    ps: *mut DenseBoard,
    mut out: *mut u8,
    reserved_space: i64,
) -> i64 {
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
/// (e.g. Heartbleed was a buffer over-read vulnerability)
/// Make sure you own the memory you read from!
///
/// Returns a null pointer if the deserialization failed.
/// Returns a pointer to a DenseBoard if the deserialization was successful.
///
/// # Safety
///
/// The bincode_ptr must point to a valid u8 array with at least reserved_space.
#[no_mangle]
pub unsafe extern "C" fn deserialize(bincode_ptr: *mut u8, reserved_space: i64) -> *mut DenseBoard {
    // Convert the pointer to a slice
    let bincode_slice = std::slice::from_raw_parts(bincode_ptr, reserved_space as usize);

    let board: Result<DenseBoard, _> = bincode::deserialize(bincode_slice);
    match board {
        Err(e) => {
            println!("Deserialization Error: {:?}", e);
            std::ptr::null_mut()
        }
        Ok(board) => leak_to_julia(board),
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
/// The index & tensor representation is documented at: /doc/ml_representation.md
///
/// # Arguments
///
/// * `ps` - A pointer to a DenseBoard instance.
/// * `out` - A pointer to a memory block of at least reserved_space u32.
/// * `reserved_space` - The number of u32 that are reserved in the out memory block.
/// * `opts` - A u32 integer, used as 32 bitflags.
///
/// # Error States
///
/// * If `reserved_space` is smaller than required for `opts`, the function
///   will return -1.
/// * If `opts` is invalid, the function will return -2.
/// * If representation Building fails, the function will return -3.
///
/// # Safety
///
/// To make this function safe to call, you need to ensure that ps points to
/// a valid DenseBoard. Additionally, the `out` pointer must point to a memory
/// block of at least reserved_space u32.
pub unsafe extern "C" fn get_idxrepr_opts(
    ps: *mut DenseBoard,
    out: *mut u32,
    reserved_space: i64,
    opts: u32,
) -> i64 {
    let Ok(options) = FlexibleRepresentationOptions::new(opts) else {
        return -2;
    };

    // Ensure that at least 38 u32 are reserved.
    if reserved_space < options.index_representation_length() as i64 {
        return -1;
    }

    let ps: &mut DenseBoard = &mut *ps;
    // Turn out into a slice for the safe code to use
    let out: &mut [u32] = std::slice::from_raw_parts_mut(out, reserved_space as usize);

    let Ok(repr) = options.index_representation(ps) else {
        return -3;
    };

    repr.write_to(out);

    0 // Everything went fine
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
#[deprecated] // use get_idxrepr_opts
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

/// Checks if two DenseBoard instances are equal.
/// Returns 0 (success code) if they are equal, 1 if they are not.
///
/// # Safety
///
/// To make this function safe to call, you need to ensure that ps1 and ps2
/// point to valid DenseBoard instances.
#[no_mangle]
pub unsafe extern "C" fn equals(ps1: *mut DenseBoard, ps2: *mut DenseBoard) -> i64 {
    let ps1: &DenseBoard = unsafe { &*ps1 };
    let ps2: &DenseBoard = unsafe { &*ps2 };

    if ps1 == ps2 {
        0
    } else {
        1
    }
}

/// Calculates a hash of a DenseBoard instance. This is not guaranteed to be
/// stable across versions.
///
/// # Safety
///
/// To make this function safe to call, you need to ensure that ps points to a
/// valid DenseBoard instance.
#[no_mangle]
pub unsafe extern "C" fn hash(ps: *mut DenseBoard) -> u64 {
    use std::hash::{Hash, Hasher};
    let ps: &DenseBoard = unsafe { &*ps };
    let mut hasher = FxHasher::default();
    ps.hash(&mut hasher);
    hasher.finish()
}

/// Returns a random position.
#[no_mangle]
pub extern "C" fn random_position() -> *mut DenseBoard {
    leak_to_julia(rand::random())
}

/// Checks if the current player is in check.
///
/// # Safety
///
/// To make this function safe to call, you need to ensure that ps points to a
/// valid DenseBoard instance.
#[no_mangle]
pub unsafe extern "C" fn is_sako_for_other_player(ps: *mut DenseBoard) -> bool {
    let ps: &DenseBoard = unsafe { &*ps };
    analysis::is_sako(ps, ps.controlling_player.other()).unwrap()
}

/// Returns a number between 0 and 64 that counts how many squares are threatened
/// by the current player.
///
/// # Safety
///
/// To make this function safe to call, you need to ensure that ps points to a
/// valid DenseBoard instance.
#[no_mangle]
pub unsafe extern "C" fn my_threat_count(ps: *mut DenseBoard) -> i64 {
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
///
/// # Safety
///
/// To make this function safe to call, you need to ensure that ps points to a
/// valid DenseBoard instance.
/// Additionally, you need to ensure that out points to a memory block of at least
/// reserved_space u8.
#[no_mangle]
pub unsafe extern "C" fn find_paco_sequences(
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
    for (hash, board) in explored.by_hash.into_iter() {
        if explored.settled.contains(&hash) && board.king_in_union(ps.controlling_player.other()) {
            if let Some(trace) = crate::trace_first_move(hash, &explored.found_via) {
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

/// Turns a DenseBoard into its FEN representation. This does not retain all
/// information, so it is not fully reversible. Most history is lost.
///
/// Returns 0 if the fen_string does not fit into the reserved space.
/// Returns the length of the fen_string otherwise.
///
/// # Safety
///
/// To make this function safe to call, you need to ensure that ps points to a
/// valid DenseBoard instance.
/// Additionally, you need to ensure that out points to a memory block of at least
/// reserved_space u8.
#[no_mangle]
pub unsafe extern "C" fn write_fen(ps: *mut DenseBoard, out: *mut u8, reserved_space: i64) -> i64 {
    let ps: &DenseBoard = unsafe { &*ps };

    let fen_string = fen::write_fen(ps);
    write_byte_string(&fen_string, out, reserved_space)
}

unsafe fn write_byte_string(string: &str, out: *mut u8, reserved_space: i64) -> i64 {
    let string = string.as_bytes();
    if string.len() as i64 > reserved_space {
        return 0;
    }

    for (i, c) in string.iter().enumerate() {
        unsafe {
            let cell = out.add(i);
            *cell = *c;
        }
    }

    string.len() as i64
}

/// Parses a FEN string into a DenseBoard.
///
/// Returns a pointer to the DenseBoard if the FEN string was valid.
/// Returns null if the FEN string was invalid. Either because it was invalid
/// utf8 or because it was not a valid FEN string.
///
/// # Safety
///
/// To make this function safe to call, you need to ensure that fen_ptr points to a
/// valid memory block of at least reserved_space u8.
#[no_mangle]
pub unsafe extern "C" fn parse_fen(mut fen_ptr: *mut u8, reserved_space: i64) -> *mut DenseBoard {
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

/// Test module
#[cfg(test)]
mod tests {

    use crate::{substrate::dense::DenseSubstrate, DenseBoard};

    /// Checks if a DenseBoard can be serialized and deserialized without
    /// breaking. Thomas reported this as broken on 2023-12-02.
    /// The error can be provoked entirely in rust without any julia code.
    #[test]
    fn serialize_deserialize() {
        let board = DenseBoard::new();
        let serialized = bincode::serialize(&board).unwrap();
        println!("Serialized Board: {:?}", serialized);
        let _deserialized: DenseBoard = bincode::deserialize(&serialized).unwrap();
    }

    #[test]
    fn serialize_deserialize_experimental() {
        let board = DenseSubstrate::default();

        let serialized = bincode::serialize(&board).unwrap();
        println!("Serialized Substrate: {:?}", serialized);
        let _deserialized: DenseSubstrate = bincode::deserialize(&serialized).unwrap();
    }
}
