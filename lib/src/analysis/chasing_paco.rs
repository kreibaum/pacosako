//! This module implements an algorithm to determine if a given board position
//! is "Chasing Paco in n" or not. This is a simplification of "Forced Paco in n"
//! where the player to win must always put its opponent in Ŝako. This reduces
//! the number of positions we need to analyze.

use core::panic;

use crate::{
    analysis::{self},
    determine_all_moves, trace_first_move, DenseBoard, PacoAction, PacoBoard, PacoError,
    PlayerColor, VictoryState,
};

use super::reverse_amazon_search;

pub fn my_is_sako(board: &DenseBoard, for_player: PlayerColor) -> Result<bool, PacoError> {
    let classical_result = analysis::is_sako(board, for_player)?;
    let amazon_result = reverse_amazon_search::is_sako(board, for_player)?;

    if classical_result != amazon_result {
        panic!(
            "Classical ({}) and Amazon ({}) search disagree on Ŝako for board:\n{:?}, FEN: {}",
            classical_result,
            amazon_result,
            board,
            crate::fen::write_fen(board)
        );
    }
    Ok(classical_result)
}

/// Checks if the given board state is "Chasing Paco in 2". This can use either
/// player's perspective. The board must be settled. (No active chain.)
/// Returns a vector of all moves that can be used for this chase.
///
/// If a the attacker can directly unite with the opponents king, this is not
/// considered a chasing paco in 2. (This is a chasing paco in 1.)
///
/// Note that for n == 2, the Chasing Paco is equivalent to Forced Paco.
pub fn is_chasing_paco_in_2(
    board: &DenseBoard,
    attacker: PlayerColor,
) -> Result<Vec<Vec<PacoAction>>, PacoError> {
    // We are looking for a move which puts the opponent in Ŝako.
    // We want to enumerate all of them.
    assert!(
        board.is_settled(),
        "Board must be settled to determine chasing paco in 2"
    );
    let mut result = vec![];

    let mut board = board.clone();
    board.controlling_player = attacker;

    let explored_attacks = determine_all_moves(board)?;

    // Check if one of these actually wins the game already.
    if explored_attacks
        .settled
        .iter()
        .any(|b| b.victory_state == VictoryState::PacoVictory(attacker))
    {
        return Ok(vec![]);
    }

    // Filter out the settled boards on which the opponent is in Ŝako now.
    'attacks: for attack_board in &explored_attacks.settled {
        // TODO: This does not yet use the amazon search algorithm.
        // But just swapping it in with is_sako(..) defined as
        // explore_paco_tree(..).paco_positions.is_empty() didn't work.
        // Needs more investigation. Maybe this is even a bug in the amazon search?
        if my_is_sako(attack_board, attacker)? {
            // This is a settled board to analyze further. Is there any defense
            // against Ŝako?
            // Uniting with the king is a valid defense.
            if my_is_sako(attack_board, attacker.other())? {
                continue;
            }
            assert!(
                attack_board.controlling_player == attacker.other(),
                "{}",
                crate::fen::write_fen(attack_board)
            );
            let explored_defense = determine_all_moves(attack_board.clone())?;
            // All of the defense boards must still be in Ŝako. Otherwise we can
            // escape. This then discards the attack board (and move) from the
            // options.
            for defense_board in &explored_defense.settled {
                if !my_is_sako(defense_board, attacker)? {
                    continue 'attacks;
                }
            }
            // No defense worked, we have a chasing paco in 2.
            // We note down the move that got us here.
            let trace = trace_first_move(attack_board, &explored_attacks.found_via)
                .expect("All settled states in an ExploredMoves must have a trace");
            result.push(trace);
        }
    }

    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fen;
    use crate::BoardPosition;
    use crate::PacoAction::*;

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

        let mut good_white_attacks = is_chasing_paco_in_2(&board, PlayerColor::White)?;
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

        let mut good_black_attacks = is_chasing_paco_in_2(&board, PlayerColor::Black)?;
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
