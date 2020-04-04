pub mod parser;
pub mod types;

use colored::*;
use rand::distributions::{Distribution, Standard};
use rand::seq::SliceRandom;
use rand::Rng;
use serde::{Deserialize, Serialize};
use std::collections::hash_map::Entry;
use std::collections::HashMap;
use std::collections::HashSet;
use std::collections::VecDeque;
use std::convert::TryFrom;
use std::fmt;
use std::fmt::Display;
use types::{BoardPosition, PieceType, PlayerColor};
use wasm_bindgen::prelude::*;

#[cfg(test)]
extern crate quickcheck;
#[cfg(test)]
#[macro_use(quickcheck)]
extern crate quickcheck_macros;

#[derive(Clone, Debug, Serialize)]
pub enum PacoError {
    /// You can not "Lift" when the hand is full.
    LiftFullHand,
    /// You can not "Lift" from an empty position.
    LiftEmptyPosition,
    /// You can not "Place" when the hand is empty.
    PlaceEmptyHand,
    /// You can not "Place" a pair when the target is occupied.
    PlacePairFullPosition,
    /// You can not "Promote" when no piece is sceduled to promote.
    PromoteWithoutCanditate,
    /// You can not "Promote" a pawn to a pawn.
    PromoteToPawn,
    /// You can not "Promote" a pawn to a king.
    PromoteToKing,
    /// The input JSON is malformed.
    InputJsonMalformed,
}

impl PlayerColor {
    #[allow(dead_code)]
    pub fn other(self) -> Self {
        use PlayerColor::*;
        match self {
            White => Black,
            Black => White,
        }
    }
    fn paint_string(self, input: &str) -> colored::ColoredString {
        use PlayerColor::*;
        match self {
            White => input.red(),
            Black => input.blue(),
        }
    }
}

impl PieceType {
    fn to_char(self) -> &'static str {
        use PieceType::*;

        match self {
            Pawn => "P",
            Rock => "R",
            Knight => "N",
            Bishop => "B",
            Queen => "Q",
            King => "K",
        }
    }
}

/// In a DenseBoard we reserve memory for all positions.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct DenseBoard {
    white: Vec<Option<PieceType>>,
    black: Vec<Option<PieceType>>,
    /// The player which is next to execute a move. This is different from the controlling player
    /// which can currently execute an action, when there is a promotion at the end of the turn.
    pub current_player: PlayerColor,
    lifted_piece: Hand,
    /// When a pawn is moved two squares forward, the square in between is used to check en passant.
    en_passant: Option<BoardPosition>,
    /// When a pawn is moved on the oppoments home row, you may promote it to any other piece.
    promotion: Option<BoardPosition>,
    /// Stores castling information
    castling: Castling,
}

/// Defines a random generator for Paco Ŝako games that are not over yet.
/// I.e. where both kings are still free. This works by placing the pieces
/// randomly on the board.
impl Distribution<DenseBoard> for Standard {
    fn sample<R: Rng + ?Sized>(&self, rng: &mut R) -> DenseBoard {
        let mut board = DenseBoard::new();

        // Shuffle white and black pieces around
        board.white.shuffle(rng);
        board.black.shuffle(rng);

        // Check all positions for violations
        // No pawns on the enemy home row
        for i in 0..64 {
            if i < 8 && board.black[i] == Some(PieceType::Pawn) {
                let free_index = loop {
                    let candidate = board.random_position_without_black(rng);
                    if candidate >= 8 {
                        break candidate;
                    }
                };
                board.black.swap(i, free_index);
            }
            if i >= 56 && board.white[i] == Some(PieceType::Pawn) {
                let free_index = loop {
                    let candidate = board.random_position_without_white(rng);
                    if candidate < 56 {
                        break candidate;
                    }
                };
                board.white.swap(i, free_index);
            }
        }

        // No single pawns on the own home row
        for i in 0..64 {
            if i < 8
                && board.white[i] == Some(PieceType::Pawn)
                && (board.black[i] == None || board.black[i] == Some(PieceType::King))
            {
                let free_index = loop {
                    let candidate = board.random_position_without_white(rng);
                    if candidate >= 8 && candidate < 56 {
                        break candidate;
                    }
                };
                board.white.swap(i, free_index);
            }
            if i >= 56
                && board.black[i] == Some(PieceType::Pawn)
                && (board.white[i] == None || board.white[i] == Some(PieceType::King))
            {
                let free_index = loop {
                    let candidate = board.random_position_without_black(rng);
                    if candidate >= 8 && candidate < 56 {
                        break candidate;
                    }
                };
                board.black.swap(i, free_index);
            }
        }

        // Ensure, that the king is single. (Done after all other pieces are moved).
        for i in 0..64 {
            if board.white[i] == Some(PieceType::King) && board.black[i] != None {
                let free_index = board.random_empty_position(rng);
                board.white.swap(i, free_index);
            }
            if board.black[i] == Some(PieceType::King) && board.white[i] != None {
                let free_index = board.random_empty_position(rng);
                board.black.swap(i, free_index);
            }
        }

        // Randomize current player
        board.current_player = if rng.gen() {
            PlayerColor::White
        } else {
            PlayerColor::Black
        };

        board
    }
}

#[derive(Serialize, Deserialize)]
pub struct EditorBoard {
    pieces: Vec<RestingPiece>,
}

impl From<&DenseBoard> for EditorBoard {
    fn from(dense: &DenseBoard) -> Self {
        // A normal game of Paco Ŝako will have 32 pieces on the board at any time.
        // All other boards are special and don't need to be optimized for.
        let mut pieces = Vec::with_capacity(32);

        // Iterate over all positions and construct a RestingPiece whenever we find Some(piece).
        pieces.extend(dense.white.iter().enumerate().filter_map(|p| {
            p.1.map(|piece_type| RestingPiece {
                piece_type,
                color: PlayerColor::White,
                position: BoardPosition(p.0 as u8),
            })
        }));

        pieces.extend(dense.black.iter().enumerate().filter_map(|p| {
            p.1.map(|piece_type| RestingPiece {
                piece_type,
                color: PlayerColor::Black,
                position: BoardPosition(p.0 as u8),
            })
        }));

        EditorBoard { pieces }
    }
}

impl EditorBoard {
    pub fn with_active_player(&self, current_player: PlayerColor) -> DenseBoard {
        let mut result: DenseBoard = DenseBoard {
            white: vec![None; 64],
            black: vec![None; 64],
            current_player,
            lifted_piece: Hand::Empty,
            en_passant: None,
            promotion: None,
            castling: Castling::new(),
        };

        // Copy piece from the `pieces` list into the dense arrays.
        for piece in &self.pieces {
            match piece.color {
                PlayerColor::White => {
                    result.white[piece.position.0 as usize] = Some(piece.piece_type)
                }
                PlayerColor::Black => {
                    result.black[piece.position.0 as usize] = Some(piece.piece_type)
                }
            }
        }

        result
    }
}

#[derive(Serialize, Deserialize)]
struct RestingPiece {
    piece_type: PieceType,
    color: PlayerColor,
    position: BoardPosition,
}

#[derive(Serialize, Debug)]
pub struct SakoSearchResult {
    pub white: Vec<Vec<PacoAction>>,
    pub black: Vec<Vec<PacoAction>>,
}

#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash)]
struct Castling {
    white_queen_side: bool,
    white_king_side: bool,
    black_queen_side: bool,
    black_king_side: bool,
}

impl Castling {
    /// Returns an initial Castling structure where all castling is possible
    fn new() -> Self {
        Castling {
            white_queen_side: true,
            white_king_side: true,
            black_queen_side: true,
            black_king_side: true,
        }
    }
}

/// Represents zero to two lifted pieces
/// The owner of the pieces must be tracked externally, usually this will be the current player.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
enum Hand {
    Empty,
    Single {
        piece: PieceType,
        position: BoardPosition,
    },
    Pair {
        piece: PieceType,
        partner: PieceType,
        position: BoardPosition,
    },
}

impl Hand {
    fn position(&self) -> Option<BoardPosition> {
        use Hand::*;
        match self {
            Empty => None,
            Single { position, .. } => Some(*position),
            Pair { position, .. } => Some(*position),
        }
    }
}

/// A PacoAction is an action that can be applied to a PacoBoard to modify it.
/// An action is an atomar part of a move, like picking up a piece or placing it down.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum PacoAction {
    /// Lifting a piece starts a move.
    Lift(BoardPosition),
    /// Placing the piece picked up earlier either ends a move or continues it in case of a chain.
    Place(BoardPosition),
    /// Promote the pawn that is currently up for promotion
    Promote(PieceType),
}

impl PacoAction {
    pub fn is_promotion(&self) -> bool {
        match self {
            PacoAction::Promote(_) => true,
            _ => false,
        }
    }
    pub fn position(&self) -> Option<BoardPosition> {
        match self {
            PacoAction::Lift(p) => Some(*p),
            PacoAction::Place(p) => Some(*p),
            PacoAction::Promote(_) => None,
        }
    }
}

/// The PacoBoard trait encapsulates arbitrary Board implementations.
pub trait PacoBoard: Clone + Eq + std::hash::Hash + Display {
    /// Check if a PacoAction is legal and execute it. Otherwise return an error.
    fn execute(&mut self, action: PacoAction) -> Result<&mut Self, PacoError>;
    /// List all actions that can be executed in the current state. Note that actions which leave
    /// the board in a deadend state (like lifting up a pawn that is blocked) should be included
    /// in the list as well.
    fn actions(&self) -> Vec<PacoAction>;
    /// A Paco Board is settled, if no piece is in the hand of the active player.
    /// Calling `.actions()` on a settled board should only return lift actions.
    fn is_settled(&self) -> bool;
    /// Determines if the King of a given color is united with an opponent piece.
    fn king_in_union(&self, color: PlayerColor) -> bool;
    /// The player that gets to execute the next `Lift` or `Place` action.
    fn current_player(&self) -> PlayerColor;
    /// The player that gets to execute the next action. This only differs from the current player
    /// when a promotion is still required.
    fn controlling_player(&self) -> PlayerColor;
}

impl DenseBoard {
    #[allow(dead_code)]
    pub fn new() -> Self {
        use PieceType::*;
        let mut result: Self = DenseBoard {
            white: Vec::with_capacity(64),
            black: Vec::with_capacity(64),
            current_player: PlayerColor::White,
            lifted_piece: Hand::Empty,
            en_passant: None,
            promotion: None,
            castling: Castling::new(),
        };

        // Board structure
        let back_row = vec![Rock, Knight, Bishop, Queen, King, Bishop, Knight, Rock];
        let front_row = vec![Pawn; 8];

        result
            .white
            .extend(back_row.iter().map(|&a| Option::Some(a)));
        result
            .white
            .extend(front_row.iter().map(|&a| Option::Some(a)));
        result.white.append(&mut vec![None; 64 - 16]);

        assert!(
            result.white.len() == 64,
            "Amount of white pieces is incorrect."
        );

        result.black.append(&mut vec![None; 64 - 16]);
        result
            .black
            .extend(front_row.iter().map(|&a| Option::Some(a)));
        result
            .black
            .extend(back_row.iter().map(|&a| Option::Some(a)));

        assert!(
            result.black.len() == 64,
            "Amount of black pieces is incorrect."
        );

        result
    }

    /// Creates an empty board without any figures. This is convenient to investigate
    /// simpler positions without all pieces.
    pub fn empty() -> Self {
        DenseBoard {
            white: vec![None; 64],
            black: vec![None; 64],
            current_player: PlayerColor::White,
            lifted_piece: Hand::Empty,
            en_passant: None,
            promotion: None,
            castling: Castling::new(),
        }
    }

    pub fn from_squares(squares: HashMap<BoardPosition, parser::Square>) -> Self {
        let mut result = Self::empty();
        for (position, square) in squares.iter() {
            if let Some(piece_type) = square.white {
                *result.white.get_mut(position.0 as usize).unwrap() = Some(piece_type);
            }
            if let Some(piece_type) = square.black {
                *result.black.get_mut(position.0 as usize).unwrap() = Some(piece_type);
            }
        }
        result
    }

    /// Lifts the piece of the current player in the given position of the board.
    /// Only one piece may be lifted at a time.
    fn lift(&mut self, position: BoardPosition) -> Result<&mut Self, PacoError> {
        if self.lifted_piece != Hand::Empty {
            return Err(PacoError::LiftFullHand);
        }
        // We unwrap the pieces once to remove the outer Some() from the .get_mut(..) call.
        // We still recieve an optional where None represents an empty square.
        let piece = *self.active_pieces().get(position.0 as usize).unwrap();
        let partner = *self.opponent_pieces().get(position.0 as usize).unwrap();

        if let Some(piece_type) = piece {
            if let Some(partner_type) = partner {
                self.lifted_piece = Hand::Pair {
                    piece: piece_type,
                    partner: partner_type,
                    position,
                };
                *self
                    .opponent_pieces_mut()
                    .get_mut(position.0 as usize)
                    .unwrap() = None;
            } else {
                self.lifted_piece = Hand::Single {
                    piece: piece_type,
                    position,
                };
            }
            *self
                .active_pieces_mut()
                .get_mut(position.0 as usize)
                .unwrap() = None;
            Ok(self)
        } else {
            Err(PacoError::LiftEmptyPosition)
        }
    }

    /// Places the piece that is currently lifted back on the board.
    /// Returns an error if no piece is currently being lifted.
    fn place(&mut self, target: BoardPosition) -> Result<&mut Self, PacoError> {
        match self.lifted_piece {
            Hand::Empty => Err(PacoError::PlaceEmptyHand),
            Hand::Single { piece, position } => {
                // If the target position is the current en passant square, pull back the opponent pawn.
                // We can't just assume that a pawn placed on the en passant square is striking
                // en passant, as the current player may also free their own pawn from a union.
                if self.en_passant == Some(target)
                    && piece == PieceType::Pawn
                    && position.advance_pawn(self.current_player) != Some(target)
                {
                    let en_passant_source_square = target
                        .advance_pawn(self.current_player().other())
                        .unwrap()
                        .0 as usize;
                    self.white.swap(target.0 as usize, en_passant_source_square);
                    self.black.swap(target.0 as usize, en_passant_source_square);
                }

                // If a pawn is moved onto the opponents home row, track promotion.
                if piece == PieceType::Pawn
                    && target.home_row() == Some(self.current_player.other())
                {
                    self.promotion = Some(target)
                }

                // Read piece currently on the board at the target position and place the
                // held piece there.
                let board_piece = *self.active_pieces().get(target.0 as usize).unwrap();
                *self.active_pieces_mut().get_mut(target.0 as usize).unwrap() = Some(piece);
                if let Some(new_hand_piece) = board_piece {
                    self.lifted_piece = Hand::Single {
                        piece: new_hand_piece,
                        position: target,
                    };
                } else {
                    // If a pawn is advanced two steps from the home row, store en passant information.
                    if piece == PieceType::Pawn
                        && position.in_pawn_row(self.current_player)
                        && (target.y() as i8 - position.y() as i8).abs() == 2
                    {
                        // Store en passant information.
                        // Note that the meaning of `None` changes from "could not advance pawn"
                        // to "capture en passant is not possible". This is fine as we checked
                        // `in_pawn_row` first and are sure this won't happen.
                        self.en_passant = position.advance_pawn(self.current_player);
                    }

                    self.lifted_piece = Hand::Empty;
                    self.current_player = self.current_player.other();
                }
                Ok(self)
            }
            Hand::Pair {
                piece,
                partner,
                position,
            } => {
                let board_piece = self.active_pieces().get(target.0 as usize).unwrap();
                let board_partner = self.opponent_pieces().get(target.0 as usize).unwrap();

                if board_piece.is_some() || board_partner.is_some() {
                    Err(PacoError::PlacePairFullPosition)
                } else {
                    // If a pawn is advanced two steps from the home row, store en passant information.
                    if piece == PieceType::Pawn
                        && position.in_pawn_row(self.current_player)
                        && (target.y() as i8 - position.y() as i8).abs() == 2
                    {
                        // Store en passant information.
                        // Note that the meaning of `None` changes from "could not advance pawn"
                        // to "capture en passant is not possible". This is fine as we checked
                        // `in_pawn_row` first and are sure this won't happen.
                        self.en_passant = position.advance_pawn(self.current_player);
                    }

                    // If a pawn is moved onto the opponents home row, track promotion.
                    let promote_own_piece = piece == PieceType::Pawn
                        && target.home_row() == Some(self.current_player.other());
                    let promote_partner_piece = partner == PieceType::Pawn
                        && target.home_row() == Some(self.current_player);
                    if promote_own_piece || promote_partner_piece {
                        self.promotion = Some(target)
                    }

                    *self.active_pieces_mut().get_mut(target.0 as usize).unwrap() = Some(piece);
                    *self
                        .opponent_pieces_mut()
                        .get_mut(target.0 as usize)
                        .unwrap() = Some(partner);
                    self.lifted_piece = Hand::Empty;
                    self.current_player = self.current_player.other();
                    Ok(self)
                }
            }
        }
    }

    /// Promotes the current promotion target to the given type.
    fn promote(&mut self, new_type: PieceType) -> Result<&mut Self, PacoError> {
        if new_type == PieceType::Pawn {
            Err(PacoError::PromoteToPawn)
        } else if new_type == PieceType::King {
            Err(PacoError::PromoteToKing)
        } else if let Some(target) = self.promotion {
            // Here we .unwrap() instead of returning an error, because a promotion target outside
            // the home row indicates an error as does a promotion target without a piece at that
            // position.
            let owner = target.home_row().unwrap().other();
            let promoted_pawn: &mut Option<PieceType> = self
                .pieces_of_color_mut(owner)
                .get_mut(target.0 as usize)
                .unwrap();
            // assert_eq!(*promoted_pawn, Some(PieceType::Pawn));
            if *promoted_pawn != Some(PieceType::Pawn) {
                panic!();
            }

            *promoted_pawn = Some(new_type);
            self.promotion = None;

            Ok(self)
        } else {
            Err(PacoError::PromoteWithoutCanditate)
        }
    }

    /// The Dense Board representation containing only pieces of the given color.
    fn pieces_of_color(&self, color: PlayerColor) -> &Vec<Option<PieceType>> {
        match color {
            PlayerColor::White => &self.white,
            PlayerColor::Black => &self.black,
        }
    }

    /// The Dense Board representation containing only pieces of the given color. (mutable borrow)
    fn pieces_of_color_mut(&mut self, color: PlayerColor) -> &mut Vec<Option<PieceType>> {
        match color {
            PlayerColor::White => &mut self.white,
            PlayerColor::Black => &mut self.black,
        }
    }

    /// The Dense Board representation containing only pieces of the current player.
    fn active_pieces(&self) -> &Vec<Option<PieceType>> {
        self.pieces_of_color(self.current_player)
    }

    /// The Dense Board representation containing only pieces of the opponent player.
    fn opponent_pieces(&self) -> &Vec<Option<PieceType>> {
        self.pieces_of_color(self.current_player.other())
    }

    /// The Dense Board representation containing only pieces of the current player.
    fn active_pieces_mut(&mut self) -> &mut Vec<Option<PieceType>> {
        self.pieces_of_color_mut(self.current_player)
    }

    /// The Dense Board representation containing only pieces of the opponent player.
    fn opponent_pieces_mut(&mut self) -> &mut Vec<Option<PieceType>> {
        match self.current_player {
            PlayerColor::White => &mut self.black,
            PlayerColor::Black => &mut self.white,
        }
    }

    /// All positions where the active player has a piece.
    fn active_positions<'a>(&'a self) -> impl Iterator<Item = BoardPosition> + 'a {
        // The filter map takes (usize, Optional<PieceType>) and returns Optional<BoardPosition>
        // where we just place the index in a Some whenever a piece is found.
        self.active_pieces()
            .iter()
            .enumerate()
            .filter_map(|p| p.1.map(|_| BoardPosition(p.0 as u8)))
    }

    /// All place target for a piece of given type at a given position.
    /// This is intended to recieve its own lifted piece as input but will work if the
    /// input piece is different.
    fn place_targets(
        &self,
        position: BoardPosition,
        piece_type: PieceType,
        is_pair: bool,
    ) -> Vec<BoardPosition> {
        use PieceType::*;
        match piece_type {
            Pawn => self.place_targets_pawn(position, is_pair),
            Rock => self.place_targets_rock(position, is_pair),
            Knight => self.place_targets_knight(position, is_pair),
            Bishop => self.place_targets_bishop(position, is_pair),
            Queen => self.place_targets_queen(position, is_pair),
            King => self.place_targets_king(position),
        }
    }

    /// Calculates all possible placement targets for a pawn at the given position.
    fn place_targets_pawn(&self, position: BoardPosition, is_pair: bool) -> Vec<BoardPosition> {
        use PlayerColor::White;
        let mut possible_moves = Vec::new();

        let forward = if self.current_player == White { 1 } else { -1 };

        // Striking left & right, this is only possible if there is a target
        // and in particular this is never possible for a pair.
        if !is_pair {
            let strike_directions = [(-1, forward), (1, forward)];
            let targets_on_board = strike_directions.iter().filter_map(|d| position.add(*d));

            targets_on_board
                .filter(|p| self.opponent_present(*p) || self.en_passant == Some(*p))
                .for_each(|p| possible_moves.push(p));
        }

        // Moving forward, this is similar to a king
        if let Some(step) = position.add((0, forward)) {
            if self.is_empty(step) {
                possible_moves.push(step);
                // If we are on the base row, check if we can move another step.
                let base_row = if self.current_player == White { 1 } else { 6 };
                if position.y() == base_row {
                    if let Some(step_2) = step.add((0, forward)) {
                        if self.is_empty(step_2) {
                            possible_moves.push(step_2);
                        }
                    }
                }
            }
        }

        // TODO: En passant, see https://en.wikipedia.org/wiki/En_passant

        possible_moves
    }
    /// Calculates all possible placement targets for a rock at the given position.
    fn place_targets_rock(&self, position: BoardPosition, is_pair: bool) -> Vec<BoardPosition> {
        let directions = vec![(1, 0), (0, 1), (-1, 0), (0, -1)];
        directions
            .iter()
            .flat_map(|d| self.slide_targets(position, *d, is_pair))
            .collect()
    }
    /// Calculates all possible placement targets for a knight at the given position.
    fn place_targets_knight(&self, position: BoardPosition, is_pair: bool) -> Vec<BoardPosition> {
        let offsets = vec![
            (1, 2),
            (2, 1),
            (2, -1),
            (1, -2),
            (-1, -2),
            (-2, -1),
            (-2, 1),
            (-1, 2),
        ];
        let targets_on_board = offsets.iter().filter_map(|d| position.add(*d));
        if is_pair {
            targets_on_board.filter(|p| self.is_empty(*p)).collect()
        } else {
            targets_on_board
                .filter(|p| self.can_place_single_at(*p))
                .collect()
        }
    }
    /// Calculates all possible placement targets for a bishop at the given position.
    fn place_targets_bishop(&self, position: BoardPosition, is_pair: bool) -> Vec<BoardPosition> {
        let directions = vec![(1, 1), (-1, 1), (1, -1), (-1, -1)];
        directions
            .iter()
            .flat_map(|d| self.slide_targets(position, *d, is_pair))
            .collect()
    }
    /// Calculates all possible placement targets for a queen at the given position.
    fn place_targets_queen(&self, position: BoardPosition, is_pair: bool) -> Vec<BoardPosition> {
        let directions = vec![
            (0, 1),
            (1, 1),
            (1, 0),
            (1, -1),
            (0, -1),
            (-1, -1),
            (-1, 0),
            (-1, 1),
        ];
        directions
            .iter()
            .flat_map(|d| self.slide_targets(position, *d, is_pair))
            .collect()
    }
    /// Calculates all possible placement targets for a king at the given position.
    fn place_targets_king(&self, position: BoardPosition) -> Vec<BoardPosition> {
        let offsets = vec![
            (0, 1),
            (1, 1),
            (1, 0),
            (1, -1),
            (0, -1),
            (-1, -1),
            (-1, 0),
            (-1, 1),
        ];
        let targets_on_board = offsets.iter().filter_map(|d| position.add(*d));
        // Placing the king works like placing a pair, as he can only be placed on empty squares.
        targets_on_board.filter(|p| self.is_empty(*p)).collect()

        // TODO: Casteling. This depends on a working Ŝako solver, as the king must not be
        // in Ŝako in order to castle.
    }
    /// Decide whether the current player may place a single lifted piece at the indicated position.
    ///
    /// This is only forbidden when the target position holds a piece of the own color
    /// without a dance partner.
    fn can_place_single_at(&self, target: BoardPosition) -> bool {
        self.opponent_present(target) || !self.active_piece_present(target)
    }
    /// Is there an opponent (i.e. a piece of current_player.other()) at the target location?
    fn opponent_present(&self, target: BoardPosition) -> bool {
        self.opponent_pieces()
            .get(target.0 as usize)
            .unwrap()
            .is_some()
    }
    /// Is there a piece of the current player at the target location?
    fn active_piece_present(&self, target: BoardPosition) -> bool {
        self.active_pieces()
            .get(target.0 as usize)
            .unwrap()
            .is_some()
    }
    /// Decide whethe a pair may be placed at the indicated position.
    ///
    /// This is only allowed if the position is completely empty.
    fn is_empty(&self, target: BoardPosition) -> bool {
        self.white.get(target.0 as usize).unwrap().is_none()
            && self.black.get(target.0 as usize).unwrap().is_none()
    }
    /// Calculates all targets by sliding step by step in a given direction and stopping at the
    /// first obstacle or at the end of the board.
    fn slide_targets(
        &self,
        start: BoardPosition,
        (dx, dy): (i8, i8),
        is_pair: bool,
    ) -> Vec<BoardPosition> {
        let mut possible_moves = Vec::new();
        let mut slide = start.add((dx, dy));

        // This while loop leaves if we drop off the board or if we hit a target.
        // The is_pair parameter determines, if the first thing we hit is a valid target.
        while let Some(target) = slide {
            if self.is_empty(target) {
                possible_moves.push(target);
                slide = target.add((dx, dy));
            } else if !is_pair && self.can_place_single_at(target) {
                possible_moves.push(target);
                slide = None;
            } else {
                slide = None;
            }
        }
        possible_moves
    }

    /// Used for random board generation
    /// This will not terminate if the board is full.
    /// The runtime of this function is not deterministic. (Geometric distribution)
    fn random_empty_position<R: Rng + ?Sized>(&self, rng: &mut R) -> usize {
        loop {
            let candidate = rng.gen_range(0, 64);
            if self.white[candidate] == None && self.black[candidate] == None {
                return candidate;
            }
        }
    }

    /// Used for random board generation
    /// This will not terminate if the board is full.
    /// The runtime of this function is not deterministic. (Geometric distribution)
    fn random_position_without_white<R: Rng + ?Sized>(&self, rng: &mut R) -> usize {
        loop {
            let candidate = rng.gen_range(0, 64);
            if self.white[candidate] == None {
                return candidate;
            }
        }
    }

    /// Used for random board generation
    /// This will not terminate if the board is full.
    /// The runtime of this function is not deterministic. (Geometric distribution)
    fn random_position_without_black<R: Rng + ?Sized>(&self, rng: &mut R) -> usize {
        loop {
            let candidate = rng.gen_range(0, 64);
            if self.black[candidate] == None {
                return candidate;
            }
        }
    }
}

impl PacoBoard for DenseBoard {
    fn execute(&mut self, action: PacoAction) -> Result<&mut Self, PacoError> {
        use PacoAction::*;
        match action {
            Lift(position) => self.lift(position),
            Place(position) => self.place(position),
            Promote(new_type) => self.promote(new_type),
        }
    }
    fn actions(&self) -> Vec<PacoAction> {
        use PacoAction::*;
        if self.promotion.is_some() {
            return vec![
                Promote(PieceType::Bishop),
                Promote(PieceType::Rock),
                Promote(PieceType::Knight),
                Promote(PieceType::Queen),
            ];
        }

        match self.lifted_piece {
            Hand::Empty => {
                // If no piece is lifted up, then we just return lifting actions of all pieces of
                // the current player.
                self.active_positions().map(Lift).collect()
            }
            Hand::Single { piece, position } => {
                // the player currently lifts a piece, we calculate all possible positions where
                // it can be placed down. This takes opponents pieces in considerations but won't
                // discard chaining into a blocked pawn (or simmilar).
                self.place_targets(position, piece, false)
                    .iter()
                    .map(|p| Place(*p))
                    .collect()
            }
            Hand::Pair {
                piece, position, ..
            } => self
                .place_targets(position, piece, true)
                .iter()
                .map(|p| Place(*p))
                .collect(),
        }
    }
    fn is_settled(&self) -> bool {
        self.lifted_piece == Hand::Empty
    }
    fn king_in_union(&self, color: PlayerColor) -> bool {
        let (king_pos, _) = self
            .pieces_of_color(color)
            .iter()
            .enumerate()
            .find(|&(_, &p)| p == Some(PieceType::King))
            .unwrap();

        self.pieces_of_color(color.other())[king_pos].is_some()
    }
    fn current_player(&self) -> PlayerColor {
        self.current_player
    }
    fn controlling_player(&self) -> PlayerColor {
        if let Some(target) = self.promotion {
            target.home_row().unwrap().other()
        } else {
            self.current_player()
        }
    }
}

impl Default for DenseBoard {
    fn default() -> Self {
        Self::new()
    }
}

/// Represents a board state in human readable exchange notation for Paco Ŝako.
/// It will look like this. Line breaks are included in the String as '\n'.
///
///     .. .. .. .B .. .. .. ..
///     .B R. .. .. .Q .. .. P.
///     .. .P .P .K .. NP P. ..
///     PR .R PP .. .. .. .. ..
///     K. .P P. .. NN .. .. ..
///     P. .P .. P. .. .. BP R.
///     P. .. .P .. .. .. BN Q.
///     .. .. .. .. .. .. .. ..
#[derive(Debug, Clone)]
pub struct ExchangeNotation(pub String);

impl From<&DenseBoard> for ExchangeNotation {
    fn from(board: &DenseBoard) -> Self {
        let mut f = String::with_capacity(191);

        for y in (0..8).rev() {
            for x in 0..8 {
                let coord = BoardPosition::new(x, y).0 as usize;
                let w = board.white.get(coord).unwrap();
                f.push_str(w.map(PieceType::to_char).unwrap_or("."));

                let b = board.black.get(coord).unwrap();
                f.push_str(b.map(PieceType::to_char).unwrap_or("."));

                if x != 7 {
                    f.push_str(" ");
                }
            }
            if y != 0 {
                f.push_str("\n");
            }
        }
        assert_eq!(f.len(), 191);
        ExchangeNotation(f)
    }
}

impl TryFrom<&ExchangeNotation> for DenseBoard {
    type Error = ();
    fn try_from(notation: &ExchangeNotation) -> Result<Self, ()> {
        if let Some(matrix) = parser::try_exchange_notation(&notation.0) {
            Ok(DenseBoard::from_squares(matrix.0))
        } else {
            Err(())
        }
    }
}

impl Display for DenseBoard {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        use PlayerColor::*;
        writeln!(f, "╔═══════════════════════════╗")?;
        let mut trailing_bracket = false;
        let highlighted_position = self.lifted_piece.position().map(|p| p.0 as usize);
        for y in (0..8).rev() {
            write!(f, "║ {}", y + 1)?;
            for x in 0..8 {
                let coord = BoardPosition::new(x, y).0 as usize;
                let w = self.white.get(coord).unwrap();
                let b = self.black.get(coord).unwrap();

                if trailing_bracket {
                    write!(f, ")")?;
                    trailing_bracket = false;
                } else if Some(coord) == highlighted_position {
                    write!(f, "(")?;
                    trailing_bracket = true;
                } else {
                    write!(f, " ")?;
                }

                match w {
                    Some(piece) => {
                        write!(f, "{}", White.paint_string(piece.to_char()))?;
                    }
                    None => {
                        write!(f, ".")?;
                    }
                };

                match b {
                    Some(piece) => {
                        write!(f, "{}", Black.paint_string(piece.to_char()))?;
                    }
                    None => {
                        write!(f, ".")?;
                    }
                };
            }
            writeln!(f, " ║")?;
        }

        match self.lifted_piece {
            Hand::Empty => writeln!(
                f,
                "║ {} A  B  C  D  E  F  G  H  ║",
                self.current_player.paint_string("*")
            )?,
            Hand::Single { piece, .. } => {
                writeln!(
                    f,
                    "║ {} A  B  C  D  E  F  G  H  ║",
                    self.current_player.paint_string(piece.to_char())
                )?;
            }
            Hand::Pair { piece, partner, .. } => {
                let (w, b) = match self.current_player {
                    PlayerColor::White => (piece, partner),
                    PlayerColor::Black => (partner, piece),
                };
                writeln!(
                    f,
                    "║{}{} A  B  C  D  E  F  G  H  ║",
                    White.paint_string(w.to_char()),
                    Black.paint_string(b.to_char())
                )?;
            }
        }
        write!(f, "╚═══════════════════════════╝")?;
        Ok(())
    }
}

/// Given a board state, this function finds all possible end states where a piece dances with the
/// opponent's king.
pub fn analyse_sako(board: impl PacoBoard) -> Result<(), PacoError> {
    println!("The input board position is");
    println!("{}", board);

    let explored = determine_all_moves(board)?;
    println!(
        "I found {} possible resulting states in total.",
        explored.settled.len()
    );

    println!("I found the following ŝako sequences:");
    // Is there a state where the black king is dancing?
    for board in explored.settled {
        if board.king_in_union(board.current_player()) {
            println!("{}", board);
            println!("{:?}", trace_first_move(&board, &explored.found_via));
        }
    }

    Ok(())
}

struct ExploredState<T: PacoBoard> {
    settled: HashSet<T>,
    found_via: HashMap<T, Vec<(PacoAction, Option<T>)>>,
}

/// Defines an algorithm that determines all moves.
/// A move is a sequence of legal actions Lift(p1), Place(p2), Place(p3), ..
/// which ends with an empty hand.
///
/// Essentially I am investigating a finite, possibly cyclic, directed graph where some nodes
/// are marked (settled boards) and I wish to find all acyclic paths from the root to these
/// marked (settled) nodes.
fn determine_all_moves<T: PacoBoard>(board: T) -> Result<ExploredState<T>, PacoError> {
    let mut todo_list: VecDeque<T> = VecDeque::new();
    let mut settled: HashSet<T> = HashSet::new();
    let mut found_via: HashMap<T, Vec<(PacoAction, Option<T>)>> = HashMap::new();

    // Put all starting moves into the initialisation
    for action in board.actions() {
        let mut b = board.clone();
        b.execute(action)?;
        found_via
            .entry(b.clone())
            .and_modify(|v| v.push((action, None)))
            .or_insert_with(|| vec![(action, None)]);
        todo_list.push_back(b);
    }

    // Pull entries from the todo_list until it is empty.
    while let Some(todo) = todo_list.pop_front() {
        // Execute all actions and look at the resulting board state.
        for action in todo.actions() {
            let mut b = todo.clone();
            b.execute(action)?;
            // look up if this action has already been found.
            match found_via.entry(b.clone()) {
                // We have seen this state already and don't need to add it to the todo list.
                Entry::Occupied(mut o_entry) => {
                    // TODO: Check for a cycle.
                    o_entry.get_mut().push((action, Some(todo.clone())));
                }
                // We encounter this state for the first time.
                Entry::Vacant(v_entry) => {
                    v_entry.insert(vec![(action, Some(todo.clone()))]);
                    if b.is_settled() {
                        // The state is settled, we don't look at the following moves.
                        settled.insert(b);
                    } else {
                        // We will look at the possible chain moves later.
                        todo_list.push_back(b);
                    }
                }
            }
        }
    }

    Ok(ExploredState { settled, found_via })
}

/// Traces a action sequence to the `target` state via the `found_via` map.
/// Note that this sequence is not uniqe. This function returns the "first" where "first"
/// depends on the order in which actions were determined.
/// Termination of this function depends on implementation details of `determine_all_moves`.
/// Returns None when no path can be found.
fn trace_first_move<T: PacoBoard>(
    target: &T,
    found_via: &HashMap<T, Vec<(PacoAction, Option<T>)>>,
) -> Option<Vec<PacoAction>> {
    let mut trace: Vec<PacoAction> = Vec::new();

    let mut pivot = target;

    loop {
        let parents = found_via.get(pivot)?;
        let (action, parent) = parents.get(0)?;
        trace.push(*action);
        if let Some(p) = parent {
            pivot = p;
        } else {
            trace.reverse();
            return Some(trace);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use parser::Square;
    use std::convert::{TryFrom, TryInto};

    fn find_sako_states<T: PacoBoard>(board: T) -> Result<Vec<T>, PacoError> {
        let opponent = board.current_player().other();

        Ok(determine_all_moves(board)?
            .settled
            .drain()
            .filter(|b| b.king_in_union(opponent))
            .collect())
    }

    #[test]
    fn test_simple_sako() {
        let mut squares = HashMap::new();
        squares.insert("c4".try_into().unwrap(), Square::white(PieceType::Bishop));
        squares.insert("f7".try_into().unwrap(), Square::black(PieceType::King));

        let sako_states = find_sako_states(DenseBoard::from_squares(squares)).unwrap();

        assert_eq!(sako_states.len(), 1);
    }

    #[test]
    fn test_simple_non_sako() {
        let mut squares = HashMap::new();
        squares.insert("c4".try_into().unwrap(), Square::white(PieceType::Bishop));
        squares.insert("f8".try_into().unwrap(), Square::black(PieceType::King));

        let sako_states = find_sako_states(DenseBoard::from_squares(squares)).unwrap();

        assert_eq!(sako_states.len(), 0);
    }

    #[test]
    fn test_chain_sako() {
        let mut squares = HashMap::new();
        squares.insert("c4".try_into().unwrap(), Square::white(PieceType::Bishop));
        squares.insert(
            "f7".try_into().unwrap(),
            Square::pair(PieceType::Rock, PieceType::Pawn),
        );
        squares.insert("f5".try_into().unwrap(), Square::black(PieceType::King));

        let sako_states = find_sako_states(DenseBoard::from_squares(squares)).unwrap();

        assert_eq!(sako_states.len(), 1);
    }

    #[test]
    fn test_en_passant() {
        use PieceType::Pawn;

        // Setup a situaltion where en passant can happen.
        let mut squares = HashMap::new();
        // White pawn that moves two squares forward
        squares.insert("d2".try_into().unwrap(), Square::white(Pawn));
        // Black pawn that will unite en passant
        squares.insert("e4".try_into().unwrap(), Square::black(Pawn));
        // White pawn to block the black pawn from advancing, reducing the black action space.
        squares.insert(BoardPosition::new(4, 2), Square::white(Pawn));
        let mut board = DenseBoard::from_squares(squares);

        // Advance the white pawn and lift the black pawn.
        board
            .execute(PacoAction::Lift("d2".try_into().unwrap()))
            .unwrap()
            .execute(PacoAction::Place("d4".try_into().unwrap()))
            .unwrap()
            .execute(PacoAction::Lift("e4".try_into().unwrap()))
            .unwrap();

        // Check if the correct legal moves are returned
        assert_eq!(
            board.actions(),
            vec![PacoAction::Place("d3".try_into().unwrap())]
        );

        // Execute en passant union
        board
            .execute(PacoAction::Place("d3".try_into().unwrap()))
            .unwrap();

        // Check if the target pawn was indeed united.
        assert_eq!(
            *board
                .white
                .get(BoardPosition::try_from("d3").unwrap().0 as usize)
                .unwrap(),
            Some(Pawn)
        );
    }

    /// This test sets up a situation where a sako through a chain is possible using en passant.
    #[test]
    fn en_passant_chain_sako() {
        use PieceType::*;

        // Setup a situation where en passant can happen.
        let mut squares = HashMap::new();
        squares.insert("c4".try_into().unwrap(), Square::black(Pawn));
        squares.insert("d2".try_into().unwrap(), Square::pair(Pawn, Knight));
        squares.insert("e1".try_into().unwrap(), Square::white(King));

        let mut board = DenseBoard::from_squares(squares);
        board
            .execute(PacoAction::Lift("d2".try_into().unwrap()))
            .unwrap()
            .execute(PacoAction::Place("d4".try_into().unwrap()))
            .unwrap();

        let sako_states = find_sako_states(board).unwrap();

        assert_eq!(sako_states.len(), 1);
    }

    /// Simple test that moves a pawn onto the opponents home row and checks promotion options.
    #[test]
    fn promote_pawn() {
        use PieceType::*;
        use PlayerColor::*;

        let mut squares = HashMap::new();
        squares.insert("c7".try_into().unwrap(), Square::white(Pawn));

        let mut board = DenseBoard::from_squares(squares);
        board
            .execute(PacoAction::Lift("c7".try_into().unwrap()))
            .unwrap()
            .execute(PacoAction::Place("c8".try_into().unwrap()))
            .unwrap();

        assert_eq!(board.promotion, Some("c8".try_into().unwrap()));
        assert_eq!(board.current_player(), Black);
        assert_eq!(board.controlling_player(), White);
        assert_eq!(
            board.actions(),
            vec![
                PacoAction::Promote(PieceType::Bishop),
                PacoAction::Promote(PieceType::Rock),
                PacoAction::Promote(PieceType::Knight),
                PacoAction::Promote(PieceType::Queen),
            ]
        );
    }

    /// Tests chaining through a pawn promotion
    /// For simplicity, the king is set up so that the pawn must promote to a knight.
    #[test]
    fn promotion_chain_sako() {
        use PieceType::*;

        let mut squares = HashMap::new();
        // Note that King on c8 does not lead to a unique ŝako.
        squares.insert("d6".try_into().unwrap(), Square::black(King));
        squares.insert("d7".try_into().unwrap(), Square::white(Pawn));
        squares.insert("e8".try_into().unwrap(), Square::pair(Bishop, Pawn));
        squares.insert("f7".try_into().unwrap(), Square::pair(Bishop, Pawn));

        let board = DenseBoard::from_squares(squares);

        let sako_states = find_sako_states(board).unwrap();

        assert_eq!(sako_states.len(), 1);
    }

    /// Tests if the white king side castleing is provided as an action when lifting the king.
    // #[test]
    // fn white_king_side_castle() {
    //     use PieceType::*;

    //     let mut squares = HashMap::new();
    //     squares.insert("e1".try_into().unwrap(), Square::white(King));
    //     squares.insert("h1".try_into().unwrap(), Square::white(Rock));
    //     let mut board = DenseBoard::from_squares(squares);
    //     board.castling.white_queen_side = false;

    //     board
    //         .execute(PacoAction::Lift("e1".try_into().unwrap()))
    //         .unwrap();

    //     assert!(board
    //         .actions()
    //         .contains(&PacoAction::Place("g1".try_into().unwrap())));
    // }

    /// Tests if the white king side castleing is blocked by an owned piece.
    #[test]
    fn white_king_side_castle_blocked_piece() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert("e1".try_into().unwrap(), Square::white(King));
        squares.insert("f1".try_into().unwrap(), Square::white(Bishop));
        squares.insert("h1".try_into().unwrap(), Square::white(Rock));
        let mut board = DenseBoard::from_squares(squares);
        board.castling.white_queen_side = false;

        board
            .execute(PacoAction::Lift("e1".try_into().unwrap()))
            .unwrap();

        assert!(!board
            .actions()
            .contains(&PacoAction::Place("g1".try_into().unwrap())));
    }

    /// Tests if the white king side castleing is blocked by an opponent sako.
    #[test]
    fn white_king_side_castle_blocked_sako() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert("e1".try_into().unwrap(), Square::white(King));
        squares.insert("b5".try_into().unwrap(), Square::black(Bishop));
        squares.insert("h1".try_into().unwrap(), Square::white(Rock));
        let mut board = DenseBoard::from_squares(squares);
        board.castling.white_queen_side = false;

        board
            .execute(PacoAction::Lift("e1".try_into().unwrap()))
            .unwrap();

        assert!(!board
            .actions()
            .contains(&PacoAction::Place("g1".try_into().unwrap())));
    }

    #[test]
    fn random_dense_board_consistent() {
        use rand::{thread_rng, Rng};

        let mut rng = thread_rng();
        for _ in 0..1000 {
            let board: DenseBoard = rng.gen();

            let mut whites_found = 0;
            let mut blacks_found = 0;

            // Check all positions for violations
            for i in 0..64 {
                // Count pieces
                if board.white[i].is_some() {
                    whites_found += 1;
                }
                if board.black[i].is_some() {
                    blacks_found += 1;
                }

                // The king should be single
                if board.white[i] == Some(PieceType::King) {
                    assert_eq!(board.black[i], None, "The white king is united.\n{}", board);
                }
                if board.black[i] == Some(PieceType::King) {
                    assert_eq!(board.white[i], None, "The black king is united.\n{}", board);
                }
                // No pawns on the enemy home row
                // No single pawns on the own home row
                if i < 8 {
                    assert_ne!(
                        board.black[i],
                        Some(PieceType::Pawn),
                        "There is a black pawn on the white home row\n{}",
                        board
                    );
                    if board.black[i] == None {
                        assert_ne!(
                            board.white[i],
                            Some(PieceType::Pawn),
                            "There is a single white pawn on the white home row\n{}",
                            board
                        );
                    }
                }
                if i >= 56 {
                    assert_ne!(
                        board.white[i],
                        Some(PieceType::Pawn),
                        "There is a white pawn on the black home row\n{}",
                        board
                    );
                    if board.white[i] == None {
                        assert_ne!(
                            board.black[i],
                            Some(PieceType::Pawn),
                            "There is a single black pawn on the black home row\n{}",
                            board
                        );
                    }
                }
            }
            assert_eq!(whites_found, 16);
            assert_eq!(blacks_found, 16);
        }
    }
}

pub fn find_sako_sequences(board: &EditorBoard) -> Result<SakoSearchResult, PacoError> {
    let mut white = vec![];
    let mut black = vec![];

    let white_board = board.with_active_player(PlayerColor::White);
    let explored = determine_all_moves(white_board)?;
    // Is there a state where the black king is dancing?
    for board in explored.settled {
        if board.king_in_union(PlayerColor::Black) {
            if let Some(trace) = trace_first_move(&board, &explored.found_via) {
                white.push(trace);
            }
        }
    }

    let black_board = board.with_active_player(PlayerColor::Black);
    let explored = determine_all_moves(black_board)?;
    // Is there a state where the black king is dancing?
    for board in explored.settled {
        if board.king_in_union(PlayerColor::White) {
            if let Some(trace) = trace_first_move(&board, &explored.found_via) {
                black.push(trace);
            }
        }
    }

    Ok(SakoSearchResult { white, black })
}

#[wasm_bindgen]
pub fn find_sako_sequences_json(board: &str) -> String {
    let editor_board: EditorBoard = serde_json::from_str(board).unwrap();
    let search_result = find_sako_sequences(&editor_board);

    match search_result {
        Ok(search_result) => serde_json::to_string(&search_result).unwrap(),
        Err(error) => serde_json::to_string(&error).unwrap(),
    }
}
