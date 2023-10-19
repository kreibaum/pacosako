//! This module implements an algorithm to determine if a given board position
//! is "Chasing Paco in n" or not. This is a simplification of "Forced Paco in n"
//! where the player to win must always put its opponent in Ŝako. This reduces
//! the number of positions we need to analyze.

use crate::{
    analysis::{self},
    determine_all_moves, trace_first_move, DenseBoard, PacoAction, PacoBoard, PacoError,
    PlayerColor,
};

/// Checks if the given board state is "Chasing Paco in 2". This can use either
/// player's perspective. The board must be settled. (No active chain.)
/// Returns a vector of all moves that can be used for this chase.
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

    // Filter out the settled boards on which the opponent is in Ŝako now.
    'attacks: for attack_board in &explored_attacks.settled {
        if analysis::is_sako(attack_board, attacker)? {
            // This is a settled board to analyze further. Is there any defense
            // against Ŝako?
            // Uniting with the king is a valid defense.
            if analysis::is_sako(attack_board, attacker.other())? {
                continue;
            }
            assert!(attack_board.controlling_player == attacker.other());
            let explored_defense = determine_all_moves(attack_board.clone())?;
            // All of the defense boards must still be in Ŝako. Otherwise we can
            // escape. This then discards the attack board (and move) from the
            // options.
            for defense_board in &explored_defense.settled {
                if !analysis::is_sako(defense_board, attacker)? {
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
}
