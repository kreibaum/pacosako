//! Module for constant bitboards. These are bitboards that are precomputed and
//! stored in the code. This is done to avoid having to compute them at runtime.

use super::BitBoard;

#[rustfmt::skip]
pub const KNIGHT_TARGETS: [BitBoard; 64] = [BitBoard(132096), BitBoard(329728),
    BitBoard(659712), BitBoard(1319424), BitBoard(2638848), BitBoard(5277696),
    BitBoard(10489856), BitBoard(4202496), BitBoard(33816580), BitBoard(84410376),
    BitBoard(168886289), BitBoard(337772578), BitBoard(675545156), BitBoard(1351090312),
    BitBoard(2685403152), BitBoard(1075839008), BitBoard(8657044482), BitBoard(21609056261),
    BitBoard(43234889994), BitBoard(86469779988), BitBoard(172939559976), BitBoard(345879119952), 
    BitBoard(687463207072), BitBoard(275414786112), BitBoard(2216203387392), BitBoard(5531918402816),
    BitBoard(11068131838464), BitBoard(22136263676928), BitBoard(44272527353856),
    BitBoard(88545054707712), BitBoard(175990581010432), BitBoard(70506185244672),
    BitBoard(567348067172352), BitBoard(1416171111120896), BitBoard(2833441750646784),
    BitBoard(5666883501293568), BitBoard(11333767002587136), BitBoard(22667534005174272),
    BitBoard(45053588738670592), BitBoard(18049583422636032), BitBoard(145241105196122112),
    BitBoard(362539804446949376), BitBoard(725361088165576704), BitBoard(1450722176331153408),
    BitBoard(2901444352662306816), BitBoard(5802888705324613632), BitBoard(11533718717099671552),
    BitBoard(4620693356194824192), BitBoard(288234782788157440), BitBoard(576469569871282176),
    BitBoard(1224997833292120064), BitBoard(2449995666584240128), BitBoard(4899991333168480256),
    BitBoard(9799982666336960512), BitBoard(1152939783987658752), BitBoard(2305878468463689728),
    BitBoard(1128098930098176), BitBoard(2257297371824128), BitBoard(4796069720358912),
    BitBoard(9592139440717824), BitBoard(19184278881435648), BitBoard(38368557762871296),
    BitBoard(4679521487814656), BitBoard(9077567998918656)];

#[cfg(test)]
mod test {
    use super::*;
    use crate::BoardPosition;
    use std::ops::Add;

    #[test]
    fn test_knights() {
        let offsets = [
            (1, 2),
            (2, 1),
            (2, -1),
            (1, -2),
            (-1, -2),
            (-2, -1),
            (-2, 1),
            (-1, 2),
        ];

        let mut recomputed: [BitBoard; 64] = [BitBoard(0); 64];

        for from in BoardPosition::all() {
            let targets_on_board = offsets.iter().filter_map(|d| from.add(*d));
            for target in targets_on_board {
                recomputed[from.0 as usize].insert(target);
            }
        }

        // Print everything: useful for debugging.
        print!("[");
        for from in BoardPosition::all() {
            print!("{:?}, ", recomputed[from.0 as usize]);
        }
        print!("]");

        assert_eq!(KNIGHT_TARGETS, recomputed);
    }
}
