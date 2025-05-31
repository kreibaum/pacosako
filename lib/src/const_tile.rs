use crate::BoardPosition;

/// Const fn that takes a value like "c3" and returns a BoardPosition.
/// This panics if it is not a valid position. You should only use it on constants.
/// This is also why we have that lifetime requirement.
const fn pos(s: &'static str) -> BoardPosition {
    assert!(s.len() == 2);
    let file = s.as_bytes()[0] - b'a';
    let rank = s.as_bytes()[1] - b'1';
    BoardPosition::new(file, rank)
}

// Yes, this looks stupid, but it is nice to reference the positions by name
// in other places of the code.

pub const A1: BoardPosition = pos("a1");
pub const A2: BoardPosition = pos("a2");
pub const A3: BoardPosition = pos("a3");
pub const A4: BoardPosition = pos("a4");
pub const A5: BoardPosition = pos("a5");
pub const A6: BoardPosition = pos("a6");
pub const A7: BoardPosition = pos("a7");
pub const A8: BoardPosition = pos("a8");
pub const B1: BoardPosition = pos("b1");
pub const B2: BoardPosition = pos("b2");
pub const B3: BoardPosition = pos("b3");
pub const B4: BoardPosition = pos("b4");
pub const B5: BoardPosition = pos("b5");
pub const B6: BoardPosition = pos("b6");
pub const B7: BoardPosition = pos("b7");
pub const B8: BoardPosition = pos("b8");
pub const C1: BoardPosition = pos("c1");
pub const C2: BoardPosition = pos("c2");
pub const C3: BoardPosition = pos("c3");
pub const C4: BoardPosition = pos("c4");
pub const C5: BoardPosition = pos("c5");
pub const C6: BoardPosition = pos("c6");
pub const C7: BoardPosition = pos("c7");
pub const C8: BoardPosition = pos("c8");
pub const D1: BoardPosition = pos("d1");
pub const D2: BoardPosition = pos("d2");
pub const D3: BoardPosition = pos("d3");
pub const D4: BoardPosition = pos("d4");
pub const D5: BoardPosition = pos("d5");
pub const D6: BoardPosition = pos("d6");
pub const D7: BoardPosition = pos("d7");
pub const D8: BoardPosition = pos("d8");
pub const E1: BoardPosition = pos("e1");
pub const E2: BoardPosition = pos("e2");
pub const E3: BoardPosition = pos("e3");
pub const E4: BoardPosition = pos("e4");
pub const E5: BoardPosition = pos("e5");
pub const E6: BoardPosition = pos("e6");
pub const E7: BoardPosition = pos("e7");
pub const E8: BoardPosition = pos("e8");
pub const F1: BoardPosition = pos("f1");
pub const F2: BoardPosition = pos("f2");
pub const F3: BoardPosition = pos("f3");
pub const F4: BoardPosition = pos("f4");
pub const F5: BoardPosition = pos("f5");
pub const F6: BoardPosition = pos("f6");
pub const F7: BoardPosition = pos("f7");
pub const F8: BoardPosition = pos("f8");
pub const G1: BoardPosition = pos("g1");
pub const G2: BoardPosition = pos("g2");
pub const G3: BoardPosition = pos("g3");
pub const G4: BoardPosition = pos("g4");
pub const G5: BoardPosition = pos("g5");
pub const G6: BoardPosition = pos("g6");
pub const G7: BoardPosition = pos("g7");
pub const G8: BoardPosition = pos("g8");
pub const H1: BoardPosition = pos("h1");
pub const H2: BoardPosition = pos("h2");
pub const H3: BoardPosition = pos("h3");
pub const H4: BoardPosition = pos("h4");
pub const H5: BoardPosition = pos("h5");
pub const H6: BoardPosition = pos("h6");
pub const H7: BoardPosition = pos("h7");
pub const H8: BoardPosition = pos("h8");

#[cfg(test)]
mod tests {
    use crate::{const_tile::pos, BoardPosition};

    /// Verify that for all valid positions, the pos function returns the correct BoardPosition.
    /// This is done by turning a BoardPosition into a string and then back into a BoardPosition.
    #[test]
    fn pos_test() {
        for rank in 0..8 {
            for file in 0..8 {
                let position = BoardPosition::new(file, rank);
                let string = position.to_string();
                // This transmutes the lifetime to 'static to call pos.
                let position2 = pos(unsafe { std::mem::transmute::<&str, &'static str>(&string) });
                assert_eq!(position, position2);
            }
        }
    }
}
