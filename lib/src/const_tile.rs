use crate::BoardPosition;

/// Const fn that takes a value like "c3" and returns a BoardPosition.
/// This panics if it is not a valid position. You should only use it on constants.
/// This is also why we have that lifetime requirement.
pub const fn pos(s: &'static str) -> BoardPosition {
    assert!(s.len() == 2);
    let file = s.as_bytes()[0] as u8 - b'a';
    let rank = s.as_bytes()[1] as u8 - b'1';
    BoardPosition::new(file, rank)
}

#[cfg(test)]
mod tests {
    use crate::{const_tile::pos, BoardPosition};

    /// Verify that for all valid positions the pos function returns the correct BoardPosition.
    /// This is done my turning a BoardPosition into a string and then back into a BoardPosition.
    #[test]
    fn pos_test() {
        for rank in 0..8 {
            for file in 0..8 {
                let position = BoardPosition::new(file, rank);
                let string = position.to_string();
                let position2 = pos(unsafe { std::mem::transmute::<&str, &'static str>(&string) });
                assert_eq!(position, position2);
            }
        }
    }
}
