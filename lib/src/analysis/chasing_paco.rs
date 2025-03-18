//! This module implements an algorithm to determine if a given board position
//! is "Chasing Paco in n" or not. This is a simplification of "Forced Paco in n"
//! where the player to win must always put its opponent in Ŝako. This reduces
//! the number of positions we need to analyze.

use crate::{
    determine_all_moves, trace_first_move, DenseBoard, PacoAction, PacoBoard, PacoError,
    PlayerColor, VictoryState,
};
use reverse_amazon_search::is_sako;

use super::reverse_amazon_search;

/// Checks if the given board state is "Chasing Paco in 2". This can use either
/// player's perspective. The board must be settled. (No active chain.)
/// Returns a vector of all moves that can be used for this chase.
///
/// If the attacker can directly unite with the opponent's king, this is not
/// considered a chasing paco in 2. (This is a chasing paco in 1.)
///
/// Note that for n == 2, the Chasing Paco is equivalent to Forced Paco.
pub fn is_chasing_paco_in_2(
    board: &DenseBoard,
    attacker: PlayerColor,
) -> Result<Vec<(DenseBoard, Vec<PacoAction>)>, PacoError> {
    // We are looking for a move which puts the opponent in Ŝako.
    // We want to enumerate all of them.
    assert!(
        board.is_settled(),
        "Board must be settled to determine chasing paco in 2"
    );
    let mut result: Vec<(DenseBoard, Vec<PacoAction>)> = vec![];

    let mut board = board.clone();
    board.controlling_player = attacker;

    let explored_attacks = determine_all_moves(board)?;

    // Check if one of these actually wins the game already.
    if explored_attacks
        .by_hash
        .values()
        .any(|b| b.victory_state == VictoryState::PacoVictory(attacker))
    {
        return Ok(vec![]);
    }

    // Filter out the settled boards on which the opponent is in Ŝako now.
    'attacks: for attack_hash in &explored_attacks.settled {
        let attack_board = &explored_attacks.by_hash[attack_hash];
        if is_sako(attack_board, attacker)? {
            // This is a settled board to analyze further. Is there any defense
            // against Ŝako?
            // Uniting with the king is a valid defense.
            let for_player = attacker.other();
            if is_sako(attack_board, for_player)? {
                continue;
            }
            assert_eq!(attack_board.controlling_player, attacker.other(), "{}", crate::fen::write_fen(attack_board));
            let explored_defense = determine_all_moves(attack_board.clone())?;
            // All the defense boards must still be in Ŝako. Otherwise, we can
            // escape. This then discards the attack board (and move) from the
            // options.
            for defense_hash in &explored_defense.settled {
                let defense_board = &explored_defense.by_hash[defense_hash];
                if !is_sako(defense_board, attacker)? {
                    continue 'attacks;
                }
            }
            // No defense worked, we have a chasing paco in 2.
            // We note down the move that got us here.
            let trace = trace_first_move(*attack_hash, &explored_attacks.found_via)
                .expect("All settled states in an ExploredMoves must have a trace");
            result.push((attack_board.clone(), trace));
        }
    }

    Ok(result)
}

#[cfg(test)]
mod tests {
    use crate::fen;
    use crate::BoardPosition;
    use crate::PacoAction::*;

    use super::*;

    fn pos(identifier: &str) -> BoardPosition {
        BoardPosition::try_from(identifier).unwrap()
    }

    macro_rules! action_chain {
        ($first:expr $(, $rest:expr)*) => {
            vec![
                Lift(pos($first))
                $(, Place(pos($rest)))*
            ]
        };
    }

    #[test]
    fn initial_board_is_no_chasing_paco() -> Result<(), PacoError> {
        let setup = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w 0 AHah - -";
        let board = fen::parse_fen(setup).unwrap();

        assert!(is_chasing_paco_in_2(&board, PlayerColor::White)?.is_empty());
        assert!(is_chasing_paco_in_2(&board, PlayerColor::Black)?.is_empty());
        Ok(())
    }

    #[test]
    fn chasing_paco_2_detected_example_a() -> Result<(), PacoError> {
        let setup = "r2q2k1/ppp1n2p/4c2e/3f1C2/1b1O1p1P/2S1P3/PPP2PP1/2KR1B2 w 0 AHah - -";
        let board = fen::parse_fen(setup).unwrap();

        let mut good_white_attacks =
            strip_board_information(is_chasing_paco_in_2(&board, PlayerColor::White)?);
        good_white_attacks.sort_by_key(|x| x.len());

        for good_attack in &good_white_attacks {
            println!("Good white attack: {:?}", good_attack);
        }

        assert_eq!(good_white_attacks.len(), 2);
        assert_eq!(good_white_attacks[0], action_chain!("d1", "d4", "e6", "g6"));
        assert_eq!(
            good_white_attacks[1],
            action_chain!("d1", "d4", "f5", "e6", "g6")
        );

        assert!(is_chasing_paco_in_2(&board, PlayerColor::Black)?.is_empty());
        Ok(())
    }

    #[test]
    fn chasing_paco_2_detected_example_b() -> Result<(), PacoError> {
        let setup = "1k3b2/p3ppp1/e1d2r2/1S1rP2p/P2P4/4A3/1PP1I1PP/2s2YRK w 0 AHah - -";
        let board = fen::parse_fen(setup).unwrap();

        let mut good_black_attacks =
            strip_board_information(is_chasing_paco_in_2(&board, PlayerColor::Black)?);
        good_black_attacks.sort_by_key(|x| x.len());

        for good_attack in &good_black_attacks {
            println!("Good black attack: {:?}", good_attack);
        }

        assert!(good_black_attacks.contains(&action_chain!("d5", "b5", "e2", "g3")));
        assert!(good_black_attacks.contains(&action_chain!["f6", "f1", "e2", "g3"]));
        assert!(good_black_attacks.contains(&action_chain!["f6", "f1", "c1", "e2", "g3"]));
        assert!(good_black_attacks.contains(&action_chain![
            "f6", "f1", "e2", "c1", "e2", "b5", "e2", "g3"
        ]));
        assert!(good_black_attacks.contains(&action_chain![
            "d5", "b5", "e2", "c1", "e2", "f1", "e2", "g3"
        ]));
        assert!(good_black_attacks.contains(&action_chain![
            "d5", "b5", "e2", "c1", "e2", "f1", "c1", "e2", "g3"
        ]));
        assert!(good_black_attacks.contains(&action_chain![
            "f6", "f1", "c1", "e2", "c1", "f1", "c1", "e2", "g3"
        ]));
        assert!(good_black_attacks.contains(&action_chain![
            "f6", "f1", "e2", "c1", "e2", "b5", "e2", "c1", "e2", "f1", "c1", "e2", "g3"
        ]));

        assert_eq!(good_black_attacks.len(), 8);

        // I believe this is chasing paco in 3, so a good test case for later.
        assert!(is_chasing_paco_in_2(&board, PlayerColor::White)?.is_empty());
        Ok(())
    }

    fn strip_board_information(
        attacks: Vec<(DenseBoard, Vec<PacoAction>)>,
    ) -> Vec<Vec<PacoAction>> {
        attacks.into_iter().map(|(_, a)| a).collect()
    }

    #[test]
    fn chasing_paco_2_detected_example_c() -> Result<(), PacoError> {
        let setup = "2btk2r/1pe2ppp/1P2p3/1dC5/8/P1E3A1/2sP1PP1/3LK1NR w 0 AHah - -";
        let board = fen::parse_fen(setup).unwrap();

        assert!(is_chasing_paco_in_2(&board, PlayerColor::White)?.is_empty());
        assert!(is_chasing_paco_in_2(&board, PlayerColor::Black)?.is_empty());
        Ok(())
    }

    #[test]
    fn chasing_paco_2_detected_example_d() -> Result<(), PacoError> {
        // Tests against a promotion at the end of the move "after" capturing
        // the king confusing the algorithm.
        let setup = "r1b1kb1r/pp1D1e2/q1A2n2/1Pp3pp/3f4/8/P1P2PPP/RNB1K1NR w 0 AHah - -";
        let board = fen::parse_fen(setup).unwrap();

        assert!(is_chasing_paco_in_2(&board, PlayerColor::White)?.is_empty());
        assert!(is_chasing_paco_in_2(&board, PlayerColor::Black)?.is_empty());
        Ok(())
    }
}
