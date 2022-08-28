pub mod export;
pub mod parser;
mod static_include;
pub mod types;
pub mod zobrist;

use colored::*;
use rand::distributions::{Distribution, Standard};
use rand::seq::SliceRandom;
use rand::Rng;
use serde::{Deserialize, Serialize};
use std::cmp::{max, min};
use std::collections::hash_map::Entry;
use std::collections::HashMap;
use std::collections::HashSet;
use std::collections::VecDeque;
use std::convert::TryFrom;
use std::fmt;
use std::fmt::Display;
pub use types::{BoardPosition, PieceType, PlayerColor};
use wasm_bindgen::prelude::*;
#[cfg(test)]
extern crate quickcheck;
#[cfg(test)]
#[macro_use(quickcheck)]
extern crate quickcheck_macros;

#[derive(thiserror::Error, Clone, Debug, Serialize)]
pub enum PacoError {
    #[error("You can not 'Lift' when the hand is full.")]
    LiftFullHand,
    #[error("You can not 'Lift' from an empty position.")]
    LiftEmptyPosition,
    #[error("You can not 'Place' when the hand is empty.")]
    PlaceEmptyHand,
    #[error("You can not 'Place' a pair when the target is occupied.")]
    PlacePairFullPosition,
    #[error("You can not 'Promote' when no piece is scheduled to promote.")]
    PromoteWithoutCandidate,
    #[error("You can not 'Promote' a pawn to a pawn.")]
    PromoteToPawn,
    #[error("You can not 'Promote' a pawn to a king.")]
    PromoteToKing,
    #[error("You need to have some free space to castle or to move the king.")]
    NoSpaceToMoveTheKing(BoardPosition),
    #[error("The input JSON is malformed.")]
    InputJsonMalformed,
    #[error("You are trying to execute an illegal action.")]
    ActionNotLegal,
    #[error("You are trying to execute an action sequence with zero actions.")]
    MissingInput,
    #[error("You are trying to execute an action when it is not your turn.")]
    NotYourTurn,
    #[error("Tried to place, required action is:")]
    PlacingWhenNotAllowed(RequiredAction),
    #[error("Tried to lift, required action is:")]
    LiftingWhenNotAllowed(RequiredAction),
    #[error("Tried to promote, required action is:")]
    PromotingWhenNotAllowed(RequiredAction),
}

impl PlayerColor {
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
            Rook => "R",
            Knight => "N",
            Bishop => "B",
            Queen => "Q",
            King => "K",
        }
    }
}

/// Possible states a board of Paco Ŝako can be in. The pacosako library only
/// implements automatic transition to PacoVictory in case of a Paco Ŝako for
/// either player.
///
/// Note that Drawing a game is not implemented yet. Possible draw reasons may
/// be: Repeated position x3, No progress made for 50 moves (100 half-moves) or
/// all pieces paired up. Maybe others?
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum VictoryState {
    Running,
    PacoVictory(PlayerColor),
    TimeoutVictory(PlayerColor),
    NoProgressDraw,
}

impl VictoryState {
    pub fn is_over(&self) -> bool {
        match self {
            VictoryState::Running => false,
            VictoryState::PacoVictory(_) => true,
            VictoryState::TimeoutVictory(_) => true,
            VictoryState::NoProgressDraw => true,
        }
    }
}

/// In a DenseBoard we reserve memory for all positions.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct DenseBoard {
    white: Vec<Option<PieceType>>,
    black: Vec<Option<PieceType>>,
    controlling_player: PlayerColor,
    required_action: RequiredAction,
    lifted_piece: Hand,
    /// When a pawn is moved two squares forward, the square in between is used to check en passant.
    pub en_passant: Option<(BoardPosition, PlayerColor)>,
    /// When a pawn is moved on the opponents home row, you may promote it to any other piece.
    promotion: Option<BoardPosition>,
    /// Stores castling information
    castling: Castling,
    victory_state: VictoryState,
    no_progress_half_moves: u8,
}

/// Promotions can happen at the start of your turn if the opponent moved a pair
/// containing your pawn to their home row. We need to differentiate that case
/// from promoting at the end of the turn.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum RequiredAction {
    /// Opponent gifted promotion
    PromoteThenLift,
    /// Pick up a piece to move
    Lift,
    /// Put your piece down, potentially chaining into another lifted piece
    Place,
    /// In-chain promotion
    PromoteThenPlace,
    /// Final promotion
    PromoteThenFinish,
}

impl RequiredAction {
    /// Indicates if the required action is one of the promote variants.
    pub fn is_promote(self) -> bool {
        match self {
            RequiredAction::PromoteThenLift => true,
            RequiredAction::Lift => false,
            RequiredAction::Place => false,
            RequiredAction::PromoteThenPlace => true,
            RequiredAction::PromoteThenFinish => true,
        }
    }
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
                    if (8..56).contains(&candidate) {
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
                    if (8..56).contains(&candidate) {
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
        board.controlling_player = if rng.gen() {
            PlayerColor::White
        } else {
            PlayerColor::Black
        };

        // Figure out if any castling permissions remain
        let white_king_in_position = board.white[4] == Some(PieceType::King);
        let black_king_in_position = board.black[60] == Some(PieceType::King);

        board.castling.white_queen_side =
            white_king_in_position && board.white[0] == Some(PieceType::Rook);
        board.castling.white_king_side =
            white_king_in_position && board.white[7] == Some(PieceType::Rook);
        board.castling.black_queen_side =
            black_king_in_position && board.black[56] == Some(PieceType::Rook);
        board.castling.black_king_side =
            black_king_in_position && board.black[63] == Some(PieceType::Rook);

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
    pub fn new(pieces: Vec<RestingPiece>) -> Self {
        EditorBoard { pieces }
    }

    pub fn with_active_player(&self, controlling_player: PlayerColor) -> DenseBoard {
        let mut result: DenseBoard = DenseBoard {
            white: vec![None; 64],
            black: vec![None; 64],
            controlling_player,
            required_action: RequiredAction::Lift,
            lifted_piece: Hand::Empty,
            en_passant: None,
            promotion: None,
            castling: Castling::new(),
            victory_state: VictoryState::Running,
            no_progress_half_moves: 0,
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

#[derive(Serialize, Deserialize, Clone)]
pub struct RestingPiece {
    piece_type: PieceType,
    color: PlayerColor,
    position: BoardPosition,
}

#[derive(Serialize, Debug)]
pub struct SakoSearchResult {
    pub white: Vec<Vec<PacoAction>>,
    pub black: Vec<Vec<PacoAction>>,
}

#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
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

    fn remove_rights_for_color(&mut self, current_player: PlayerColor) {
        match current_player {
            PlayerColor::White => {
                self.white_queen_side = false;
                self.white_king_side = false;
            }
            PlayerColor::Black => {
                self.black_queen_side = false;
                self.black_king_side = false;
            }
        }
    }
}

/// Represents zero to two lifted pieces
/// The owner of the pieces must be tracked externally, usually this will be the current player.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Hand {
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
    fn colored_optional_pair(
        &self,
        as_player: PlayerColor,
    ) -> (Option<PieceType>, Option<PieceType>) {
        use Hand::*;
        match self {
            Empty => (None, None),
            Single { piece, .. } => match as_player {
                PlayerColor::White => (Some(*piece), None),
                PlayerColor::Black => (None, Some(*piece)),
            },
            Pair { piece, partner, .. } => match as_player {
                PlayerColor::White => (Some(*piece), Some(*partner)),
                PlayerColor::Black => (Some(*partner), Some(*piece)),
            },
        }
    }
}

/// A PacoAction is an action that can be applied to a PacoBoard to modify it.
/// An action is an atomic part of a move, like picking up a piece or placing it down.
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
        matches!(self, PacoAction::Promote(_))
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
    /// Executes a PacoAction. This call may assume that the action is legal
    /// without checking it. Only call it when you generate the actions yourself.
    fn execute_trusted(&mut self, action: PacoAction) -> Result<&mut Self, PacoError>;
    /// List all actions that can be executed in the current state. Note that actions which leave
    /// the board in a dead-end state (like lifting up a pawn that is blocked) should be included
    /// in the list as well.
    fn actions(&self) -> Result<Vec<PacoAction>, PacoError>;
    /// List all actions, that threaten to capture a position. This means pairs
    /// are excluded and king movement is also excluded. Movement to an empty
    /// square which could capture is included. Actions which leave the
    /// board in a dead end state are included.
    fn threat_actions(&self) -> Vec<PacoAction>;
    /// A Paco Board is settled, if no piece is in the hand of the active player.
    /// Calling `.actions()` on a settled board should only return lift actions.
    fn is_settled(&self) -> bool;
    /// Determines if the King of a given color is united with an opponent piece.
    fn king_in_union(&self, color: PlayerColor) -> bool;
    /// The player that gets to execute the next action.
    fn controlling_player(&self) -> PlayerColor;
    /// Returns (white piece, black piece) for a piece that is at a given position.
    fn get_at(&self, position: BoardPosition) -> (Option<PieceType>, Option<PieceType>);
    /// Can we do an en passant capture right now?
    /// Returns false if you first need to lift a pawn to capture next turn.
    fn en_passant_capture_possible(&self) -> bool;
    /// Gets the current status of the game
    fn victory_state(&self) -> VictoryState;
}

impl DenseBoard {
    pub fn new() -> Self {
        use PieceType::*;
        let mut result: Self = DenseBoard {
            white: Vec::with_capacity(64),
            black: Vec::with_capacity(64),
            controlling_player: PlayerColor::White,
            required_action: RequiredAction::Lift,
            lifted_piece: Hand::Empty,
            en_passant: None,
            promotion: None,
            castling: Castling::new(),
            victory_state: VictoryState::Running,
            no_progress_half_moves: 0,
        };

        // Board structure
        let back_row = vec![Rook, Knight, Bishop, Queen, King, Bishop, Knight, Rook];
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
            controlling_player: PlayerColor::White,
            required_action: RequiredAction::Lift,
            lifted_piece: Hand::Empty,
            en_passant: None,
            promotion: None,
            castling: Castling::new(),
            victory_state: VictoryState::Running,
            no_progress_half_moves: 0,
        }
    }

    /// Allows you to replace the hand.
    pub fn set_hand(&mut self, new_hand: Hand) {
        self.lifted_piece = new_hand;
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

    /// To help the AIs a bit, we are not allowing it to lift any pieces that
    /// get stuck instantly. They need to have at least one position where they
    /// can be placed down again.
    fn pieces_that_can_be_lifted(&self) -> Result<Vec<PacoAction>, PacoError> {
        let mut result = vec![];

        for p in self.active_positions() {
            let is_pair = self.opponent_present(p);
            let piece = *self.active_pieces().get(p.0 as usize).unwrap();
            if let Some(piece) = piece {
                // For the King we need a special case, otherwise we would be
                // checking castling options which is expensive.
                // Since a castling option implies a move option, there is no
                // need to check for castling options.
                if piece == PieceType::King {
                    let targets = self.place_targets_king_without_castling(p);
                    if !targets.is_empty() {
                        result.push(PacoAction::Lift(p));
                    }
                } else {
                    let targets = self.place_targets(p, piece, is_pair)?;
                    if !targets.is_empty() {
                        result.push(PacoAction::Lift(p));
                    }
                }
            }
        }

        Ok(result)
    }

    /// Lifts the piece of the current player in the given position of the board.
    /// Only one piece may be lifted at a time.
    fn lift(&mut self, position: BoardPosition) -> Result<&mut Self, PacoError> {
        if self.required_action != RequiredAction::Lift {
            return Err(PacoError::LiftingWhenNotAllowed(self.required_action));
        }
        // Lifting is always followed by a place.
        self.required_action = RequiredAction::Place;

        if self.lifted_piece != Hand::Empty {
            return Err(PacoError::LiftFullHand);
        }
        // We unwrap the pieces once to remove the outer Some() from the .get_mut(..) call.
        // We still receive an optional where None represents an empty square.
        let piece = *self.active_pieces().get(position.0 as usize).unwrap();
        let partner = *self.opponent_pieces().get(position.0 as usize).unwrap();

        if let Some(piece_type) = piece {
            // When lifting a rook, castling may be forfeit.
            if piece_type == PieceType::Rook {
                if position == BoardPosition(0) && self.controlling_player == PlayerColor::White {
                    self.castling.white_queen_side = false;
                } else if position == BoardPosition(7)
                    && self.controlling_player == PlayerColor::White
                {
                    self.castling.white_king_side = false;
                } else if position == BoardPosition(56)
                    && self.controlling_player == PlayerColor::Black
                {
                    self.castling.black_queen_side = false;
                } else if position == BoardPosition(63)
                    && self.controlling_player == PlayerColor::Black
                {
                    self.castling.black_king_side = false;
                }
            }

            if let Some(partner_type) = partner {
                // When lifting an enemy rook, castling may be denied from them.
                if partner_type == PieceType::Rook {
                    if position == BoardPosition(0) && self.controlling_player == PlayerColor::Black
                    {
                        self.castling.white_queen_side = false;
                    } else if position == BoardPosition(7)
                        && self.controlling_player == PlayerColor::Black
                    {
                        self.castling.white_king_side = false;
                    } else if position == BoardPosition(56)
                        && self.controlling_player == PlayerColor::White
                    {
                        self.castling.black_queen_side = false;
                    } else if position == BoardPosition(63)
                        && self.controlling_player == PlayerColor::White
                    {
                        self.castling.black_king_side = false;
                    }
                }
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
        if self.required_action != RequiredAction::Place {
            return Err(PacoError::PlacingWhenNotAllowed(self.required_action));
        }

        match self.lifted_piece {
            Hand::Empty => Err(PacoError::PlaceEmptyHand),
            Hand::Single { piece, position } => {
                if self.is_place_using_en_passant(target, piece, position) {
                    self.do_en_passant_auxiliary_move(target);
                }

                // If a pawn is moved onto the opponents home row, track promotion.
                if piece == PieceType::Pawn
                    && target.home_row() == Some(self.controlling_player.other())
                {
                    self.promotion = Some(target)
                }

                // Special case to handle castling
                if piece == PieceType::King {
                    return self.place_king(position, target);
                }

                // Read piece currently on the board at the target position and place the
                // held piece there.
                let board_piece = *self.active_pieces().get(target.0 as usize).unwrap();
                *self.active_pieces_mut().get_mut(target.0 as usize).unwrap() = Some(piece);
                if let Some(new_hand_piece) = board_piece {
                    // This is a chain, so we track a piece in hand.
                    self.lifted_piece = Hand::Single {
                        piece: new_hand_piece,
                        position: target,
                    };
                    if self.promotion.is_some() {
                        self.required_action = RequiredAction::PromoteThenPlace;
                    } else {
                        // This should essentially be a no-op and is just here for clarity.
                        self.required_action = RequiredAction::Place;
                    }
                } else {
                    // Not a chain.

                    // Check if the half move counter goes up or down.
                    // Is there a new union we are creating?
                    if let Some(Some(_)) = self.opponent_pieces().get(target.0 as usize) {
                        self.no_progress_half_moves = 0;
                    } else {
                        // No new union -> no progress
                        // This is slightly incorrect if you are promoting a
                        // pawn in the same chain, but I think that is a detail
                        // we can fix in the board rewrite.
                        self.do_add_half_move_and_check_draw();
                    }

                    self.check_and_mark_en_passant(piece, position, target);

                    self.lifted_piece = Hand::Empty;

                    // This is the only place where we need to check if we just
                    // united with the king. This is because we can safely assume
                    // that the king was not united with any other piece before.

                    if Some(&Some(PieceType::King)) == self.opponent_pieces().get(target.0 as usize)
                    {
                        // We have united with the opponent king, the game is now won.
                        self.victory_state = VictoryState::PacoVictory(self.controlling_player);
                    }

                    // Placing without chaining means the current player switches.
                    // Note that there still may be a hanging promoting, so the
                    // active player does necessarily switch.
                    if self.promotion.is_some() {
                        self.required_action = RequiredAction::PromoteThenFinish;
                    } else {
                        self.required_action = RequiredAction::Lift;
                        self.controlling_player = self.controlling_player.other();
                    }
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
                    self.check_and_mark_en_passant(piece, position, target);

                    *self.active_pieces_mut().get_mut(target.0 as usize).unwrap() = Some(piece);
                    *self
                        .opponent_pieces_mut()
                        .get_mut(target.0 as usize)
                        .unwrap() = Some(partner);
                    self.lifted_piece = Hand::Empty;

                    // If a pawn is moved onto the opponents home row, track promotion.
                    let promote_own_piece = piece == PieceType::Pawn
                        && self.controlling_player.other().home_row() == target.y();
                    let promote_partner_piece = partner == PieceType::Pawn
                        && self.controlling_player.home_row() == target.y();
                    if promote_own_piece {
                        self.promotion = Some(target);
                        self.required_action = RequiredAction::PromoteThenFinish;
                    } else if promote_partner_piece {
                        self.promotion = Some(target);
                        self.required_action = RequiredAction::PromoteThenLift;
                        self.controlling_player = self.controlling_player.other();
                    } else {
                        self.required_action = RequiredAction::Lift;
                        self.controlling_player = self.controlling_player.other();
                    }

                    // Moving a pair never gets any progress.
                    self.do_add_half_move_and_check_draw();
                    Ok(self)
                }
            }
        }
    }

    /// If a pawn is advanced two steps from the home row, store en passant information.
    fn check_and_mark_en_passant(
        &mut self,
        piece: PieceType,
        position: BoardPosition,
        target: BoardPosition,
    ) {
        if piece == PieceType::Pawn
            && position.in_pawn_row(self.controlling_player)
            && (target.y() as i8 - position.y() as i8).abs() == 2
        {
            // Store en passant information.
            // Note that the meaning of `None` changes from "could not advance pawn"
            // to "capture en passant is not possible". This is fine as we checked
            // `in_pawn_row` first and are sure this won't happen.
            self.en_passant = Some((
                position.advance_pawn(self.controlling_player).unwrap(),
                self.controlling_player,
            ));
        }
    }

    /// Increases the half move counter. If the game is drawn, then it is set to
    /// a NoProgressDraw.
    fn do_add_half_move_and_check_draw(&mut self) {
        self.no_progress_half_moves += 1;
        if self.no_progress_half_moves == 100 {
            self.victory_state = VictoryState::NoProgressDraw;
        }
    }

    /// Detects if the given place action is using en passant.
    fn is_place_using_en_passant(
        &self,
        target_square: BoardPosition,
        piece: PieceType,
        source_square: BoardPosition,
    ) -> bool {
        // En passant only triggers for pawns.
        piece == PieceType::Pawn
            // And only if their target square is the en passant target.
            && self.en_passant == Some((target_square, self.controlling_player.other()))
            // And if the pawn is actually capturing, and not just chaining out
            // of a pair into the empty en passant square.
            && source_square.advance_pawn(self.controlling_player) != Some(target_square)
    }

    // Swaps the content of two squares. Does not touch lifted pieces.
    // Usually done for auxiliary movement like en passant or castling.
    fn swap(&mut self, pos1: BoardPosition, pos2: BoardPosition) {
        self.white.swap(pos1.0 as usize, pos2.0 as usize);
        self.black.swap(pos1.0 as usize, pos2.0 as usize);
    }

    /// Moves back the pawn to the en passant square, including the partner.
    /// This consumes the information about the en passant square so we don't
    /// see it twice in a chain.
    fn do_en_passant_auxiliary_move(&mut self, target: BoardPosition) {
        let en_passant_reset_from = target
            .advance_pawn(self.controlling_player.other())
            .unwrap();
        // Move back pair
        self.swap(target, en_passant_reset_from);

        self.en_passant = None;
    }

    fn place_king(
        &mut self,
        king_source: BoardPosition,
        king_target: BoardPosition,
    ) -> Result<&mut Self, PacoError> {
        // Moving the king does never progress the game and even
        // castling or forfeiting castling does not count as
        // progress according to FIDE rules.
        self.do_add_half_move_and_check_draw();

        if let Some((rook_source, rook_target)) =
            get_castling_auxiliary_move(king_source, king_target)
        {
            self.ensure_board_clean(king_source, king_target)?;

            // Swap rooks
            self.swap(rook_source, rook_target);
        }

        // Place down the king
        self.active_pieces_mut()
            .get_mut(king_target.0 as usize)
            .unwrap()
            .replace(PieceType::King);
        self.lifted_piece = Hand::Empty;

        // Forfeit castling rights.
        self.castling
            .remove_rights_for_color(self.controlling_player);
        self.controlling_player = self.controlling_player.other();
        self.required_action = RequiredAction::Lift;
        Ok(self)
    }

    /// Some extra safety checks to make sure we don't overwrite pieces when castling.
    fn ensure_board_clean(
        &mut self,
        king_source: BoardPosition,
        king_target: BoardPosition,
    ) -> Result<(), PacoError> {
        let king_min = min(king_source.0, king_target.0);
        let king_max = max(king_source.0, king_target.0);
        for i in (king_min + 1)..king_max {
            if !self.is_empty(BoardPosition(i)) {
                return Err(PacoError::NoSpaceToMoveTheKing(BoardPosition(i)));
            }
        }
        Ok(())
    }

    /// Promotes the current promotion target to the given type.
    fn promote(&mut self, new_type: PieceType) -> Result<&mut Self, PacoError> {
        if !self.required_action.is_promote() {
            return Err(PacoError::PromotingWhenNotAllowed(self.required_action));
        }

        if new_type == PieceType::Pawn {
            Err(PacoError::PromoteToPawn)
        } else if new_type == PieceType::King {
            Err(PacoError::PromoteToKing)
        } else if let Some(target) = self.promotion {
            // Here we .unwrap() instead of returning an error, because a promotion target outside
            // the home row indicates an error as does a promotion target without a piece at that
            // position.
            let owner = target.home_row().unwrap().other();
            assert_eq!(self.controlling_player, owner);
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

            self.no_progress_half_moves = 0;

            match self.required_action {
                RequiredAction::PromoteThenLift => {
                    self.required_action = RequiredAction::Lift;
                }
                RequiredAction::Lift => panic!("promoting when lifting should be done"),
                RequiredAction::Place => panic!("promoting when placing should be done"),
                RequiredAction::PromoteThenPlace => {
                    self.required_action = RequiredAction::Place;
                }
                RequiredAction::PromoteThenFinish => {
                    self.required_action = RequiredAction::Lift;
                    self.controlling_player = self.controlling_player.other();
                    self.en_passant = None;
                }
            }

            Ok(self)
        } else {
            Err(PacoError::PromoteWithoutCandidate)
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
        self.pieces_of_color(self.controlling_player)
    }

    /// The Dense Board representation containing only pieces of the opponent player.
    fn opponent_pieces(&self) -> &Vec<Option<PieceType>> {
        self.pieces_of_color(self.controlling_player.other())
    }

    /// The Dense Board representation containing only pieces of the current player.
    fn active_pieces_mut(&mut self) -> &mut Vec<Option<PieceType>> {
        self.pieces_of_color_mut(self.controlling_player)
    }

    /// The Dense Board representation containing only pieces of the opponent player.
    fn opponent_pieces_mut(&mut self) -> &mut Vec<Option<PieceType>> {
        match self.controlling_player {
            PlayerColor::White => &mut self.black,
            PlayerColor::Black => &mut self.white,
        }
    }

    /// All positions where the active player has a piece.
    fn active_positions(&self) -> impl Iterator<Item = BoardPosition> + '_ {
        // The filter map takes (usize, Optional<PieceType>) and returns Optional<BoardPosition>
        // where we just place the index in a Some whenever a piece is found.
        self.active_pieces()
            .iter()
            .enumerate()
            .filter_map(|p| p.1.map(|_| BoardPosition(p.0 as u8)))
    }

    /// All place target for a piece of given type at a given position.
    /// This is intended to receive its own lifted piece as input but will work if the
    /// input piece is different.
    fn place_targets(
        &self,
        position: BoardPosition,
        piece_type: PieceType,
        is_pair: bool,
    ) -> Result<Vec<BoardPosition>, PacoError> {
        use PieceType::*;
        match piece_type {
            Pawn => Ok(self.place_targets_pawn(position, is_pair)),
            Rook => Ok(self.place_targets_rock(position, is_pair, false)),
            Knight => Ok(self.place_targets_knight(position, is_pair, false)),
            Bishop => Ok(self.place_targets_bishop(position, is_pair, false)),
            Queen => Ok(self.place_targets_queen(position, is_pair, false)),
            King => self.place_targets_king(position),
        }
    }

    fn threat_place_targets(
        &self,
        position: BoardPosition,
        piece_type: PieceType,
    ) -> Vec<BoardPosition> {
        use PieceType::*;
        match piece_type {
            Pawn => self.threat_place_targets_pawn(position),
            Rook => self.place_targets_rock(position, false, true),
            Knight => self.place_targets_knight(position, false, true),
            Bishop => self.place_targets_bishop(position, false, true),
            Queen => self.place_targets_queen(position, false, true),
            King => vec![], // The king can not threaten.
        }
    }

    /// Calculates all possible placement targets for a pawn at the given position.
    fn place_targets_pawn(&self, position: BoardPosition, is_pair: bool) -> Vec<BoardPosition> {
        use PlayerColor::White;
        let mut possible_moves = Vec::new();

        let forward = self.controlling_player.forward_direction();

        // Striking left & right, this is only possible if there is a target
        // and in particular this is never possible for a pair.
        if !is_pair {
            let strike_directions = [(-1, forward), (1, forward)];
            let targets_on_board = strike_directions.iter().filter_map(|d| position.add(*d));

            let en_passant_square = self.en_passant.map(|(p, _)| p);

            targets_on_board
                .filter(|p| self.opponent_present(*p) || en_passant_square == Some(*p))
                .for_each(|p| possible_moves.push(p));
        }

        // Moving forward, this is similar to a king
        if let Some(step) = position.add((0, forward)) {
            if self.is_empty(step) {
                possible_moves.push(step);
                // If we are on the base row or further back, check if we can move another step.
                let double_move_allowed = if self.controlling_player == White {
                    position.y() <= 1
                } else {
                    position.y() >= 6
                };
                if double_move_allowed {
                    if let Some(step_2) = step.add((0, forward)) {
                        if self.is_empty(step_2) {
                            possible_moves.push(step_2);
                        }
                    }
                }
            }
        }

        possible_moves
    }
    /// Calculates all possible threat placement targets for a pawn at the given
    /// position.
    fn threat_place_targets_pawn(&self, position: BoardPosition) -> Vec<BoardPosition> {
        use PlayerColor::White;

        let forward = if self.controlling_player == White {
            1
        } else {
            -1
        };

        // Striking left & right. As we only determine threatened positions, not
        // legal moves, there is no target required.
        [(-1, forward), (1, forward)]
            .iter()
            .filter_map(|d| position.add(*d))
            .collect()
    }

    /// Calculates all possible placement targets for a rock at the given position.
    fn place_targets_rock(
        &self,
        position: BoardPosition,
        is_pair: bool,
        is_threat_detection: bool,
    ) -> Vec<BoardPosition> {
        let directions = vec![(1, 0), (0, 1), (-1, 0), (0, -1)];
        directions
            .iter()
            .flat_map(|d| self.slide_targets(position, *d, is_pair, is_threat_detection))
            .collect()
    }

    /// Calculates all possible placement targets for a knight at the given position.
    fn place_targets_knight(
        &self,
        position: BoardPosition,
        is_pair: bool,
        is_threat_detection: bool,
    ) -> Vec<BoardPosition> {
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
        if is_threat_detection {
            targets_on_board.collect()
        } else if is_pair {
            targets_on_board.filter(|p| self.is_empty(*p)).collect()
        } else {
            targets_on_board
                .filter(|p| self.can_place_single_at(*p))
                .collect()
        }
    }

    /// Calculates all possible placement targets for a bishop at the given position.
    fn place_targets_bishop(
        &self,
        position: BoardPosition,
        is_pair: bool,
        is_threat_detection: bool,
    ) -> Vec<BoardPosition> {
        let directions = vec![(1, 1), (-1, 1), (1, -1), (-1, -1)];
        directions
            .iter()
            .flat_map(|d| self.slide_targets(position, *d, is_pair, is_threat_detection))
            .collect()
    }
    /// Calculates all possible placement targets for a queen at the given position.
    fn place_targets_queen(
        &self,
        position: BoardPosition,
        is_pair: bool,
        is_threat_detection: bool,
    ) -> Vec<BoardPosition> {
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
            .flat_map(|d| self.slide_targets(position, *d, is_pair, is_threat_detection))
            .collect()
    }
    /// Calculates all possible placement targets for a king at the given position.
    fn place_targets_king(&self, position: BoardPosition) -> Result<Vec<BoardPosition>, PacoError> {
        let mut targets_on_board = self.place_targets_king_without_castling(position);

        // Threat computation is expensive so we need to make sure we only do it once.
        let mut lazy_threats: Option<[IsThreatened; 64]> = None;
        let calc_threats = || {
            // We can't just call determine_all_threats directly as the wrong
            // player is currently active and we have a king in hand.
            let mut board_clone = self.clone();
            board_clone.controlling_player = board_clone.controlling_player.other();
            board_clone.lifted_piece = Hand::Empty;
            board_clone.required_action = RequiredAction::Lift;
            determine_all_threats(&board_clone)
        };
        // Check if the castling right was not void earlier
        if self.controlling_player == PlayerColor::White && self.castling.white_queen_side {
            // Check if the spaces are empty
            if self.is_empty(BoardPosition(1))
                && self.is_empty(BoardPosition(2))
                && self.is_empty(BoardPosition(3))
            {
                // Check that there are no threats
                if lazy_threats.is_none() {
                    lazy_threats = Some(calc_threats()?);
                }
                let threats = lazy_threats.unwrap();
                if !threats[2].0 && !threats[3].0 && !threats[4].0 {
                    targets_on_board.push(BoardPosition(2));
                }
            }
        }
        if self.controlling_player == PlayerColor::White && self.castling.white_king_side {
            // Check if the spaces are empty
            if self.is_empty(BoardPosition(5)) && self.is_empty(BoardPosition(6)) {
                // Check that there are no threats
                if lazy_threats.is_none() {
                    lazy_threats = Some(calc_threats()?);
                }
                let threats = lazy_threats.unwrap();
                if !threats[4].0 && !threats[5].0 && !threats[6].0 {
                    targets_on_board.push(BoardPosition(6));
                }
            }
        }
        if self.controlling_player == PlayerColor::Black && self.castling.black_queen_side {
            // Check if the spaces are empty
            if self.is_empty(BoardPosition(57))
                && self.is_empty(BoardPosition(58))
                && self.is_empty(BoardPosition(59))
            {
                // Check that there are no threats
                if lazy_threats.is_none() {
                    lazy_threats = Some(calc_threats()?);
                }
                let threats = lazy_threats.unwrap();
                if !threats[58].0 && !threats[59].0 && !threats[60].0 {
                    targets_on_board.push(BoardPosition(58));
                }
            }
        }
        if self.controlling_player == PlayerColor::Black && self.castling.black_king_side {
            // Check if the spaces are empty
            if self.is_empty(BoardPosition(61)) && self.is_empty(BoardPosition(62)) {
                // Check that there are no threats
                if lazy_threats.is_none() {
                    lazy_threats = Some(calc_threats()?);
                }
                let threats = lazy_threats.unwrap();
                if !threats[60].0 && !threats[61].0 && !threats[62].0 {
                    targets_on_board.push(BoardPosition(62));
                }
            }
        }

        Ok(targets_on_board)
    }

    fn place_targets_king_without_castling(&self, position: BoardPosition) -> Vec<BoardPosition> {
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
        let targets_on_board: Vec<BoardPosition> = offsets
            .iter()
            .filter_map(|d| position.add(*d))
            // Placing the king works like placing a pair, as he can only be
            // placed on empty squares.
            .filter(|p| self.is_empty(*p))
            .collect();
        targets_on_board
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
    /// Decide whether a pair may be placed at the indicated position.
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
        is_threat_detection: bool,
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
                // If we are only interested in determining threats, then we
                // also count a square with a single own piece as threatened.
                if is_threat_detection {
                    possible_moves.push(target);
                }
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
            let candidate = rng.gen_range(0..64);
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
            let candidate = rng.gen_range(0..64);
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
            let candidate = rng.gen_range(0..64);
            if self.black[candidate] == None {
                return candidate;
            }
        }
    }

    // TODO: This is a good candidate to get simplified.
    fn remove_en_passant_info(&mut self) {
        if self.is_settled() {
            if let Some((_, player)) = self.en_passant {
                if player == self.controlling_player {
                    // We may use the en_passant information after a chain has
                    // been running for a while. This extra if wrapper prevents
                    // losing the information with the first place.
                    self.en_passant = None;
                }
            }
        }
    }

    fn place_actions(&self) -> Result<Vec<PacoAction>, PacoError> {
        match self.lifted_piece {
            Hand::Empty => {
                // If no piece is lifted up, then we just return lifting actions of all pieces of
                // the current player.
                self.pieces_that_can_be_lifted()
            }
            Hand::Single { piece, position } => {
                // the player currently lifts a piece, we calculate all possible positions where
                // it can be placed down. This takes opponents pieces in considerations but won't
                // discard chaining into a blocked pawn (or similar).
                Ok(self
                    .place_targets(position, piece, false)?
                    .iter()
                    .map(|p| PacoAction::Place(*p))
                    .collect())
            }
            Hand::Pair {
                piece, position, ..
            } => Ok(self
                .place_targets(position, piece, true)?
                .iter()
                .map(|p| PacoAction::Place(*p))
                .collect()),
        }
    }
}

/// For a given move of the king, determines if this would trigger a castling.
/// If so, the corresponding rook swap is returned. First square is "source",
/// the second is "target".
pub fn get_castling_auxiliary_move(
    king_source: BoardPosition,
    king_target: BoardPosition,
) -> Option<(BoardPosition, BoardPosition)> {
    if king_source == BoardPosition(4) && king_target == BoardPosition(2) {
        Some((BoardPosition(0), BoardPosition(3)))
    } else if king_source == BoardPosition(4) && king_target == BoardPosition(6) {
        Some((BoardPosition(7), BoardPosition(5)))
    } else if king_source == BoardPosition(60) && king_target == BoardPosition(58) {
        Some((BoardPosition(56), BoardPosition(59)))
    } else if king_source == BoardPosition(60) && king_target == BoardPosition(62) {
        Some((BoardPosition(63), BoardPosition(61)))
    } else {
        None
    }
}

impl PacoBoard for DenseBoard {
    fn execute(&mut self, action: PacoAction) -> Result<&mut Self, PacoError> {
        // This can be optimized a lot. But the current implementation is at
        // least easy and definitely consistent with the rules.
        if self.actions()?.contains(&action) {
            self.execute_trusted(action)
        } else {
            Err(PacoError::ActionNotLegal)
        }
    }
    fn execute_trusted(&mut self, action: PacoAction) -> Result<&mut Self, PacoError> {
        use PacoAction::*;
        match action {
            Lift(position) => self.lift(position),
            Place(position) => {
                self.place(position)?;
                self.remove_en_passant_info();
                Ok(self)
            }
            Promote(new_type) => self.promote(new_type),
        }
    }
    fn actions(&self) -> Result<Vec<PacoAction>, PacoError> {
        // If the game is over, then there are no actions.
        if self.victory_state.is_over() {
            return Ok(vec![]);
        }

        match self.required_action {
            RequiredAction::Lift => self.pieces_that_can_be_lifted(),
            RequiredAction::Place => self.place_actions(),
            RequiredAction::PromoteThenLift => all_promotion_options(),
            RequiredAction::PromoteThenPlace => all_promotion_options(),
            RequiredAction::PromoteThenFinish => all_promotion_options(),
        }
    }
    fn threat_actions(&self) -> Vec<PacoAction> {
        use PacoAction::*;
        // Promotion can threaten, because it can be done as part of a chain.
        if self.promotion.is_some() {
            return vec![
                Promote(PieceType::Bishop),
                Promote(PieceType::Rook),
                Promote(PieceType::Knight),
                Promote(PieceType::Queen),
            ];
        }

        match self.lifted_piece {
            Hand::Empty => {
                // If no piece is lifted up, then we just return lifting actions
                // of all pieces of the current player. We need to filter out
                // the king, as the king can never threaten.
                // # Rules 2017: "A king cannot be united with another piece and
                // # is therefore exempt from creating, moving or taking over a
                // # union and from the chain reaction."
                self.active_positions()
                    .filter(|position| {
                        *self.active_pieces().get(position.0 as usize).unwrap()
                            != Some(PieceType::King)
                    })
                    .map(Lift)
                    .collect()
            }
            Hand::Single { piece, position } => {
                // the player currently lifts a piece, we calculate all possible positions where
                // it can be placed down. This takes opponents pieces in considerations but won't
                // discard chaining into a blocked pawn (or similar).
                self.threat_place_targets(position, piece)
                    .iter()
                    .map(|p| Place(*p))
                    .collect()
            }
            Hand::Pair { .. } => vec![],
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
    fn controlling_player(&self) -> PlayerColor {
        self.controlling_player
    }
    fn get_at(&self, position: BoardPosition) -> (Option<PieceType>, Option<PieceType>) {
        (
            self.white.get(position.0 as usize).cloned().unwrap_or(None),
            self.black.get(position.0 as usize).cloned().unwrap_or(None),
        )
    }
    fn en_passant_capture_possible(&self) -> bool {
        if let Hand::Single {
            piece: PieceType::Pawn,
            position,
        } = self.lifted_piece
        {
            if let Some((target_position, _)) = self.en_passant {
                let forward = self.controlling_player.forward_direction();

                position.add((-1, forward)) == Some(target_position)
                    || position.add((1, forward)) == Some(target_position)
            } else {
                false
            }
        } else {
            false
        }
    }
    fn victory_state(&self) -> VictoryState {
        self.victory_state
    }
}

fn all_promotion_options() -> Result<Vec<PacoAction>, PacoError> {
    Ok(vec![
        PacoAction::Promote(PieceType::Bishop),
        PacoAction::Promote(PieceType::Rook),
        PacoAction::Promote(PieceType::Knight),
        PacoAction::Promote(PieceType::Queen),
    ])
}

impl Default for DenseBoard {
    fn default() -> Self {
        Self::new()
    }
}

/// Represents a board state in human readable exchange notation for Paco Ŝako.
/// It will look like this. Line breaks are included in the String as '\n'.
///
/// ```
/// # use pacosako::*;
/// # use std::convert::TryFrom;
/// let notation = ExchangeNotation(".. .. .. .B .. .. .. ..\\n\
/// .B R. .. .. .Q .. .. P.\\n\
/// .. .P .P .K .. NP P. ..\\n\
/// PR .R PP .. .. .. .. ..\\n\
/// K. .P P. .. NN .. .. ..\\n\
/// P. .P .. P. .. .. BP R.\\n\
/// P. .. .P .. .. .. BN Q.\\n\
/// .. .. .. .. .. .. .. ..".to_owned());
/// let board = DenseBoard::try_from( &notation ).unwrap();
/// ```
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
                    f.push(' ');
                }
            }
            if y != 0 {
                f.push('\n');
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
                self.controlling_player.paint_string("*")
            )?,
            Hand::Single { piece, .. } => {
                writeln!(
                    f,
                    "║ {} A  B  C  D  E  F  G  H  ║",
                    self.controlling_player.paint_string(piece.to_char())
                )?;
            }
            Hand::Pair { piece, partner, .. } => {
                let (w, b) = match self.controlling_player {
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
        if board.king_in_union(board.controlling_player()) {
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

    // Put all starting moves into the initialization
    for action in board.actions()? {
        let mut b = board.clone();
        b.execute_trusted(action)?;
        found_via
            .entry(b.clone())
            .and_modify(|v| v.push((action, None)))
            .or_insert_with(|| vec![(action, None)]);
        todo_list.push_back(b);
    }

    // Pull entries from the todo_list until it is empty.
    while let Some(todo) = todo_list.pop_front() {
        // Execute all actions and look at the resulting board state.
        for action in todo.actions()? {
            let mut b = todo.clone();
            b.execute_trusted(action)?;
            // look up if this action has already been found.
            match found_via.entry(b.clone()) {
                // We have seen this state already and don't need to add it to the todo list.
                Entry::Occupied(mut o_entry) => {
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
/// Note that this sequence is not unique. This function returns the "first" where "first"
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

/// A boolean value that indicates if a position is threatened.
/// This is wrapped in a custom struct to make it unambiguous what the options
/// true and false mean in this context.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct IsThreatened(bool);

/// Given a Paco Ŝako board, determines which squares are threatened by the
/// currently active player. Returns an array of booleans, one for each square.
fn determine_all_threats<T: PacoBoard>(board: &T) -> Result<[IsThreatened; 64], PacoError> {
    let mut all_threats = [IsThreatened(false); 64];

    // This needs to follow all chain moves. Non-terminal chain actions are
    // always threat actions.
    // This is simpler that determining all moves, as we don't need to keep an
    // record of how we came to a specific position.
    let mut todo_list: VecDeque<T> = VecDeque::new();
    let mut seen: HashSet<T> = HashSet::new();
    // let mut settled: HashSet<T> = HashSet::new();
    // Put all starting moves into the initialization
    for action in board.threat_actions() {
        let mut b = board.clone();
        b.execute_trusted(action)?;
        todo_list.push_back(b);
    }

    // Pull entries from the todo_list until it is empty.
    while let Some(todo) = todo_list.pop_front() {
        let actions = todo.threat_actions();

        // Mark all threats
        actions
            .iter()
            .filter_map(PacoAction::position)
            .for_each(|p| all_threats[p.0 as usize] = IsThreatened(true));

        // Follow place actions that form a chain.
        for action in todo.actions()? {
            if let PacoAction::Place(target_position) = action {
                let target_pieces = todo.get_at(target_position);
                if target_pieces.0.is_none() || target_pieces.1.is_none() {
                    // This is a very special case, but we need to test for
                    // en passant chaining.
                    if !todo.en_passant_capture_possible() {
                        continue;
                    }
                }
                // If the state has not been seen yet, and is not a settled
                // state, add it into the todo list.
                let mut b = todo.clone();
                b.execute_trusted(action)?;
                if !b.is_settled() && !seen.contains(&b) {
                    todo_list.push_back(b.clone());
                    seen.insert(b);
                }
            } else if let PacoAction::Promote(_) = action {
                // Promotion does not add threats, but extends the chain.
                let mut b = todo.clone();
                b.execute_trusted(action)?;
                if !b.is_settled() && !seen.contains(&b) {
                    todo_list.push_back(b.clone());
                    seen.insert(b);
                }
            }
        }
    }

    Ok(all_threats)
}

/// Executes a sequence of paco sako actions as a given player, if those actions
/// are legal for the given player.
pub fn execute_sequence<T: PacoBoard>(
    board: &T,
    sequence: Vec<PacoAction>,
    as_player: PlayerColor,
) -> Result<T, PacoError> {
    if sequence.is_empty() {
        // Nothing to do when we get an empty move.
        return Err(PacoError::MissingInput);
    }
    // this needs to clone the input as we may run into an error in the middle
    // of the sequence.
    let mut new_state = board.clone();
    for action in sequence {
        if new_state.controlling_player() == as_player {
            new_state.execute(action)?;
        } else {
            return Err(PacoError::NotYourTurn);
        }
    }

    Ok(new_state)
}

/// Finds the last point in the action sequence where the active player changed.
/// The action stack is assumed to only contain legal moves and the moves are
/// not validated.
pub fn find_last_checkpoint_index<'a>(
    actions: impl Iterator<Item = &'a PacoAction>,
) -> Result<usize, PacoError> {
    let mut board = DenseBoard::new();
    let mut action_counter = 0;
    let mut last_checkpoint_index = action_counter;
    let mut last_controlling_player = board.controlling_player();

    for action in actions {
        action_counter += 1;
        board.execute_trusted(*action)?;
        let new_controlling_player = board.controlling_player();
        if new_controlling_player != last_controlling_player {
            last_checkpoint_index = action_counter;
            last_controlling_player = new_controlling_player;
        }
    }

    // Check if the game is still running, otherwise we can't roll back.
    if board.victory_state().is_over() {
        return Ok(action_counter);
    }

    Ok(last_checkpoint_index)
}

#[cfg(test)]
mod tests {
    use super::*;
    use parser::Square;
    use std::convert::{TryFrom, TryInto};

    /// Helper macro to execute moves in unit tests.
    macro_rules! execute_action {
        ($board:expr, lift, $square:expr) => {{
            $board
                .execute_trusted(PacoAction::Lift($square.try_into().unwrap()))
                .unwrap();
        }};
        ($board:expr, place, $square:expr) => {{
            $board
                .execute_trusted(PacoAction::Place($square.try_into().unwrap()))
                .unwrap();
        }};
        ($board:expr, promote, $pieceType:expr) => {{
            $board
                .execute_trusted(PacoAction::Promote($pieceType))
                .unwrap();
        }};
    }

    fn pos(identifier: &str) -> BoardPosition {
        BoardPosition::try_from(identifier).unwrap()
    }

    /// Helper function to make tests of "determine all moves" easier.
    fn find_sako_states<T: PacoBoard>(board: T) -> Result<Vec<T>, PacoError> {
        let opponent = board.controlling_player().other();

        Ok(determine_all_moves(board)?
            .settled
            .drain()
            .filter(|b| b.king_in_union(opponent))
            .collect())
    }

    #[test]
    fn test_simple_sako() {
        let mut squares = HashMap::new();
        squares.insert(pos("c4"), Square::white(PieceType::Bishop));
        squares.insert(pos("f7"), Square::black(PieceType::King));

        let sako_states = find_sako_states(DenseBoard::from_squares(squares)).unwrap();

        assert_eq!(sako_states.len(), 1);
    }

    #[test]
    fn test_simple_non_sako() {
        let mut squares = HashMap::new();
        squares.insert(pos("c4"), Square::white(PieceType::Bishop));
        squares.insert(pos("f8"), Square::black(PieceType::King));

        let sako_states = find_sako_states(DenseBoard::from_squares(squares)).unwrap();

        assert_eq!(sako_states.len(), 0);
    }

    #[test]
    fn test_chain_sako() {
        let mut squares = HashMap::new();
        squares.insert(pos("c4"), Square::white(PieceType::Bishop));
        squares.insert(pos("f7"), Square::pair(PieceType::Rook, PieceType::Pawn));
        squares.insert(pos("f5"), Square::black(PieceType::King));

        let sako_states = find_sako_states(DenseBoard::from_squares(squares)).unwrap();

        assert_eq!(sako_states.len(), 1);
    }

    #[test]
    fn test_en_passant() {
        use PieceType::Pawn;

        // Setup a situation where en passant can happen.
        let mut squares = HashMap::new();
        // White pawn that moves two squares forward
        squares.insert(pos("d2"), Square::white(Pawn));
        // Black pawn that will unite en passant
        squares.insert(pos("e4"), Square::black(Pawn));
        // White pawn to block the black pawn from advancing, reducing the black action space.
        squares.insert(BoardPosition::new(4, 2), Square::white(Pawn));
        let mut board = DenseBoard::from_squares(squares);

        // Advance the white pawn and lift the black pawn.
        execute_action!(board, lift, "d2");
        execute_action!(board, place, "d4");
        execute_action!(board, lift, "e4");

        // Check if the correct legal moves are returned
        assert_eq!(pos("d3"), board.en_passant.unwrap().0);
        assert!(board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("d3"))));

        // Execute en passant union
        execute_action!(board, place, "d3");

        // Check if the target pawn was indeed united.
        assert_eq!(*board.white.get(pos("d3").0 as usize).unwrap(), Some(Pawn));
    }

    /// This test sets up a situation where a sako through a chain is possible using en passant.
    #[test]
    fn en_passant_chain_sako() {
        use PieceType::*;

        // Setup a situation where en passant can happen.
        let mut squares = HashMap::new();
        squares.insert(pos("c4"), Square::black(Pawn));
        squares.insert(pos("d2"), Square::pair(Pawn, Knight));
        squares.insert(pos("e1"), Square::white(King));
        let mut board = DenseBoard::from_squares(squares);

        execute_action!(board, lift, "d2");
        execute_action!(board, place, "d4");

        assert_eq!(pos("d3"), board.en_passant.unwrap().0);

        let sako_states = find_sako_states(board).unwrap();

        assert_eq!(sako_states.len(), 1);
    }

    /// Simple test that moves a pawn onto the opponents home row and checks promotion options.
    #[test]
    fn promote_pawn() {
        use PieceType::*;
        use PlayerColor::*;

        let mut squares = HashMap::new();
        squares.insert(pos("c7"), Square::white(Pawn));
        let mut board = DenseBoard::from_squares(squares);

        execute_action!(board, lift, "c7");
        execute_action!(board, place, "c8");

        assert_eq!(board.promotion, Some(pos("c8")));
        assert_eq!(board.controlling_player(), White);
        assert_eq!(board.required_action, RequiredAction::PromoteThenFinish);
        assert_eq!(
            board.actions().unwrap(),
            vec![
                PacoAction::Promote(PieceType::Bishop),
                PacoAction::Promote(PieceType::Rook),
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
        squares.insert(pos("d6"), Square::black(King));
        squares.insert(pos("d7"), Square::white(Pawn));
        squares.insert(pos("e8"), Square::pair(Bishop, Pawn));
        squares.insert(pos("f7"), Square::pair(Bishop, Pawn));

        let board = DenseBoard::from_squares(squares);

        let sako_states = find_sako_states(board).unwrap();

        assert_eq!(sako_states.len(), 1);
    }

    /// Checks that en_passant information is correctly recorded.
    #[test]
    fn test_en_passant_information() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(pos("c2"), Square::white(Pawn));
        squares.insert(pos("c7"), Square::black(Pawn));
        squares.insert(pos("e2"), Square::pair(Pawn, Pawn));
        squares.insert(pos("e7"), Square::pair(Pawn, Pawn));
        let mut board = DenseBoard::from_squares(squares);

        // Check that white can be captured en passant
        execute_action!(board, lift, "c2");
        execute_action!(board, place, "c4");

        assert_eq!(pos("c3"), board.en_passant.unwrap().0);

        // Check that white can be captured en passant
        execute_action!(board, lift, "c7");
        execute_action!(board, place, "c5");

        assert_eq!(pos("c6"), board.en_passant.unwrap().0);

        // Check that white can be captured en passant when they move a pair
        execute_action!(board, lift, "e2");
        execute_action!(board, place, "e4");

        assert_eq!(pos("e3"), board.en_passant.unwrap().0);

        // Check that black can be captured en passant when they move a pair
        execute_action!(board, lift, "e7");
        execute_action!(board, place, "e5");

        assert_eq!(pos("e6"), board.en_passant.unwrap().0);
    }

    /// Checks that en_passant information is correctly recorded.
    #[test]
    fn test_en_passant_information_decays() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(pos("c5"), Square::white(Pawn));
        squares.insert(pos("d5"), Square::white(Pawn));
        squares.insert(pos("e7"), Square::black(Pawn));
        squares.insert(pos("f7"), Square::black(Pawn));
        let mut board = DenseBoard::from_squares(squares);
        board.controlling_player = PlayerColor::Black;

        // Black moves, this marks e6 as en passant
        execute_action!(board, lift, "e7");
        execute_action!(board, place, "e5");

        assert_eq!(pos("e6"), board.en_passant.unwrap().0);

        // White move
        execute_action!(board, lift, "c5");
        execute_action!(board, place, "c6");

        // There should be no en passant information left
        assert_eq!(None, board.en_passant);
    }

    ////////////////////////////////////////////////////////////////////////////
    // Test threat detection ///////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    /// Test that non-chained threat detection works as expected.
    #[test]
    fn test_threat_determination() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(pos("c2"), Square::white(Pawn));
        squares.insert(pos("e3"), Square::pair(Rook, Pawn));
        squares.insert(pos("d1"), Square::white(King));
        squares.insert(pos("c5"), Square::black(Pawn));

        let board = DenseBoard::from_squares(squares);

        let received_threats = determine_all_threats(&board).unwrap();
        let mut expected_threats = [IsThreatened(false); 64];
        expected_threats[17] = IsThreatened(true);
        expected_threats[19] = IsThreatened(true);

        assert_threats(expected_threats, received_threats);
    }

    /// Here we test that chains are understood by the threat analyzer.
    /// It also tests, that a square were an own piece is located is still marked
    /// as threatened. While we don't need this for castling detection it may
    /// be useful for writing AI, especially if we follow the paper
    ///
    /// Accelerating Self-Play Learning in Go
    /// https://arxiv.org/abs/1902.10565
    #[test]
    fn test_threat_chains() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(pos("c2"), Square::white(Pawn));
        squares.insert(pos("d3"), Square::pair(Rook, Pawn));
        squares.insert(pos("g3"), Square::white(King));
        squares.insert(pos("c5"), Square::black(Pawn));

        let board = DenseBoard::from_squares(squares);

        let received_threats = determine_all_threats(&board).unwrap();
        let mut expected_threats = [IsThreatened(false); 64];
        // Rook threatens row, cut of by king
        for i in 16..23 {
            expected_threats[i] = IsThreatened(true);
        }
        // Rook threatens column
        for i in 0..8 {
            expected_threats[3 + i * 8] = IsThreatened(true);
        }
        // Pawn threats overlap with Rook threats.

        assert_threats(expected_threats, received_threats);
    }

    /// As the knight has a different behavior from sliding pieces, it gets
    /// its very own test-case.
    #[test]
    fn test_threat_knight() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(pos("c2"), Square::white(Knight));
        squares.insert(pos("b4"), Square::black(Pawn));
        squares.insert(pos("d4"), Square::pair(Pawn, Pawn));
        squares.insert(pos("f4"), Square::pair(Pawn, Pawn));
        squares.insert(pos("e3"), Square::white(King));

        let board = DenseBoard::from_squares(squares);

        let received_threats = determine_all_threats(&board).unwrap();
        let mut expected_threats = [IsThreatened(false); 64];
        // Knight threats
        expected_threats[0] = IsThreatened(true);
        expected_threats[16] = IsThreatened(true);
        expected_threats[25] = IsThreatened(true);
        expected_threats[27] = IsThreatened(true);
        expected_threats[20] = IsThreatened(true);
        expected_threats[4] = IsThreatened(true);
        // Pawn threats (from d4)
        expected_threats[34] = IsThreatened(true);
        expected_threats[36] = IsThreatened(true);

        assert_threats(expected_threats, received_threats);
    }

    /// It is possible to threaten via promoting a pawn.
    #[test]
    fn test_threat_promotion() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(pos("g7"), Square::white(Pawn));
        squares.insert(pos("g6"), Square::pair(Knight, Pawn));
        squares.insert("h8".try_into().unwrap(), Square::pair(Knight, Pawn));
        let board = DenseBoard::from_squares(squares);

        let received_threats = determine_all_threats(&board).unwrap();
        let mut expected_threats = [IsThreatened(false); 64];
        // Queen threats
        for i in 0..8 {
            // Row 7
            expected_threats[7 * 8 + i] = IsThreatened(true);
            // File h
            expected_threats[7 + 8 * i] = IsThreatened(true);
            // Main diagonal
            expected_threats[9 * i] = IsThreatened(true);
        }
        // Additional knight threats
        expected_threats[6 * 8 + 5] = IsThreatened(true);
        expected_threats[5 * 8 + 6] = IsThreatened(true);
        expected_threats[3 * 8 + 5] = IsThreatened(true);
        expected_threats[3 * 8 + 7] = IsThreatened(true);
        expected_threats[6 * 8 + 4] = IsThreatened(true);

        assert_threats(expected_threats, received_threats);
    }

    /// It is possible to do a threat chain with en passant capture
    #[test]
    fn test_threat_enpassant() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(pos("e5"), Square::white(Pawn));
        squares.insert(pos("f7"), Square::pair(Pawn, Pawn));
        let mut board = DenseBoard::from_squares(squares);
        board.controlling_player = PlayerColor::Black;

        execute_action!(board, lift, "f7");
        execute_action!(board, place, "f5");

        assert_eq!(pos("f6"), board.en_passant.unwrap().0);

        let received_threats = determine_all_threats(&board).unwrap();
        let mut expected_threats = [IsThreatened(false); 64];
        // Threats by the free pawn
        expected_threats[5 * 8 + 3] = IsThreatened(true);
        expected_threats[5 * 8 + 5] = IsThreatened(true);
        // Threats by en passant chain
        expected_threats[6 * 8 + 4] = IsThreatened(true);
        expected_threats[6 * 8 + 6] = IsThreatened(true);

        assert_threats(expected_threats, received_threats);
    }

    /// Throws with a detailed explanation, if the threats differ.
    fn assert_threats(expected: [IsThreatened; 64], received: [IsThreatened; 64]) {
        let mut differences: Vec<String> = vec![];

        for i in 0..64 {
            if expected[i] != received[i] {
                differences.push(format!(
                    "At {} I expected {} but got {}.",
                    BoardPosition(i as u8),
                    expected[i].0,
                    received[i].0
                ));
            }
        }

        if !differences.is_empty() {
            panic!("There is a difference in threats! {:?}", differences);
        }
    }

    ////////////////////////////////////////////////////////////////////////////
    // Test castling ///////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////

    /// Tests if the white king castling is provided as an action when lifting the king.
    #[test]
    fn white_castle() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(pos("e1"), Square::white(King));
        squares.insert("h1".try_into().unwrap(), Square::white(Rook));
        squares.insert(pos("a1"), Square::white(Rook));
        let mut board = DenseBoard::from_squares(squares);

        execute_action!(board, lift, "e1");
        // Queen side
        assert!(board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("c1"))));

        // King side
        assert!(board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("g1"))));

        // Moving the king also moves the rook
        execute_action!(board, place, "c1");
        assert_eq!(Some(PieceType::Rook), board.get_at(pos("d1")).0);
    }

    /// Checks that white castling kingside move the rook and the united black piece.
    #[test]
    fn white_king_castle_moves_rook() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(pos("e1"), Square::white(King));
        squares.insert("h1".try_into().unwrap(), Square::pair(Rook, Knight));
        let mut board = DenseBoard::from_squares(squares);
        execute_action!(board, lift, "e1");
        execute_action!(board, place, "g1");
        assert_eq!(Some(PieceType::Rook), board.get_at(pos("f1")).0);
        assert_eq!(Some(PieceType::Knight), board.get_at(pos("f1")).1);
    }

    /// Tests if the white king moving forfeits castling rights.
    #[test]
    fn white_king_forfeit_castle() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(pos("e1"), Square::white(King));
        squares.insert("h1".try_into().unwrap(), Square::white(Rook));
        squares.insert(pos("a1"), Square::white(Rook));
        squares.insert(pos("c7"), Square::black(Pawn));
        let mut board = DenseBoard::from_squares(squares);

        execute_action!(board, lift, "e1");
        execute_action!(board, place, "e2");
        // Black makes a move in between
        execute_action!(board, lift, "c7");
        execute_action!(board, place, "c6");
        // White moves back
        execute_action!(board, lift, "e2");
        execute_action!(board, place, "e1");
        // Black makes a move in between
        execute_action!(board, lift, "c6");
        execute_action!(board, place, "c5");
        // White should have lost castling rights now.
        execute_action!(board, lift, "e1");

        // Queen side
        assert!(!board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("c1"))));

        // King side
        assert!(!board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("g1"))));
    }

    /// Tests if the white queen rook moving forfeits castling rights.
    #[test]
    fn white_queen_rook_forfeit_castle() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(pos("e1"), Square::white(King));
        squares.insert("h1".try_into().unwrap(), Square::white(Rook));
        squares.insert(pos("a1"), Square::white(Rook));
        squares.insert(pos("c7"), Square::black(Pawn));
        let mut board = DenseBoard::from_squares(squares);

        execute_action!(board, lift, "a1");
        execute_action!(board, place, "a2");
        // Black makes a move in between
        execute_action!(board, lift, "c7");
        execute_action!(board, place, "c6");
        // White moves back
        execute_action!(board, lift, "a2");
        execute_action!(board, place, "a1");
        // Black makes a move in between
        execute_action!(board, lift, "c6");
        execute_action!(board, place, "c5");
        // White should have lost castling rights now.
        execute_action!(board, lift, "e1");

        // Queen side should be forbidden
        assert!(!board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("c1"))));

        // King side should be allowed
        assert!(board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("g1"))));
    }

    /// Tests if the white king rook moving forfeits castling rights.
    #[test]
    fn white_king_rook_forfeit_castle() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(pos("e1"), Square::white(King));
        squares.insert("h1".try_into().unwrap(), Square::white(Rook));
        squares.insert(pos("a1"), Square::white(Rook));
        squares.insert(pos("c7"), Square::black(Pawn));
        let mut board = DenseBoard::from_squares(squares);

        execute_action!(board, lift, "h1");
        execute_action!(board, place, "h2");
        // Black makes a move in between
        execute_action!(board, lift, "c7");
        execute_action!(board, place, "c6");
        // White moves back
        execute_action!(board, lift, "h2");
        execute_action!(board, place, "h1");
        // Black makes a move in between
        execute_action!(board, lift, "c6");
        execute_action!(board, place, "c5");
        // White should have lost castling rights now.
        execute_action!(board, lift, "e1");

        // Queen side should be allowed
        assert!(board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("c1"))));

        // King side should be forbidden
        assert!(!board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("g1"))));
    }

    /// Tests if the black king castling is provided as an action when lifting the king.
    #[test]
    fn black_castle() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(pos("e8"), Square::black(King));
        squares.insert("h8".try_into().unwrap(), Square::black(Rook));
        squares.insert(pos("a8"), Square::black(Rook));
        let mut board = DenseBoard::from_squares(squares);
        board.controlling_player = PlayerColor::Black;

        execute_action!(board, lift, "e8");
        // Queen side
        assert!(board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("c8"))));

        // King side
        assert!(board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("g8"))));

        // Moving the king also moves the rook
        execute_action!(board, place, "c8");
        assert_eq!(Some(PieceType::Rook), board.get_at(pos("d8")).1);
    }

    /// Checks that black castling kingside move the rook and the united white piece.
    #[test]
    fn black_king_castle_moves_rook() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(pos("e8"), Square::black(King));
        squares.insert("h8".try_into().unwrap(), Square::pair(Knight, Rook));
        let mut board = DenseBoard::from_squares(squares);
        board.controlling_player = PlayerColor::Black;

        execute_action!(board, lift, "e8");
        execute_action!(board, place, "g8");
        assert_eq!(Some(PieceType::Knight), board.get_at(pos("f8")).0);
        assert_eq!(Some(PieceType::Rook), board.get_at(pos("f8")).1);
    }

    /// Tests if the black king moving forfeits castling rights.
    #[test]
    fn black_king_forfeit_castle() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(pos("e8"), Square::black(King));
        squares.insert("h8".try_into().unwrap(), Square::black(Rook));
        squares.insert(pos("a8"), Square::black(Rook));
        squares.insert(pos("c2"), Square::white(Pawn));
        let mut board = DenseBoard::from_squares(squares);
        board.controlling_player = PlayerColor::Black;

        execute_action!(board, lift, "e8");
        execute_action!(board, place, "e7");
        // White makes a move in between
        execute_action!(board, lift, "c2");
        execute_action!(board, place, "c3");
        // Black moves back
        execute_action!(board, lift, "e7");
        execute_action!(board, place, "e8");
        // White makes a move in between
        execute_action!(board, lift, "c3");
        execute_action!(board, place, "c4");
        // Black should have lost castling rights now.
        execute_action!(board, lift, "e8");

        // Queen side
        assert!(!board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("c8"))));

        // King side
        assert!(!board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("g8"))));
    }

    /// Tests if the black queen side rook moving forfeits castling rights.
    #[test]
    fn black_queen_rook_forfeit_castle() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(pos("e8"), Square::black(King));
        squares.insert("h8".try_into().unwrap(), Square::black(Rook));
        squares.insert(pos("a8"), Square::black(Rook));
        squares.insert(pos("c2"), Square::white(Pawn));
        let mut board = DenseBoard::from_squares(squares);
        board.controlling_player = PlayerColor::Black;

        execute_action!(board, lift, "a8");
        execute_action!(board, place, "a7");
        // White makes a move in between
        execute_action!(board, lift, "c2");
        execute_action!(board, place, "c3");
        // Black moves back
        execute_action!(board, lift, "a7");
        execute_action!(board, place, "a8");
        // White makes a move in between
        execute_action!(board, lift, "c3");
        execute_action!(board, place, "c4");
        // Black should have lost castling rights now.
        execute_action!(board, lift, "e8");

        // Queen side is forbidden
        assert!(!board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("c8"))));

        // King side is allowed
        assert!(board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("g8"))));
    }

    /// You can do a chain where the rook ends up in the original position.
    /// This still forfeits the castling right.
    #[test]
    fn idempotent_chain_forfeits_castle() {
        use PieceType::*;

        let mut squares = HashMap::new();
        // General castling layout
        squares.insert(pos("e8"), Square::black(King));
        squares.insert("h8".try_into().unwrap(), Square::black(Rook));
        squares.insert(pos("a8"), Square::black(Rook));
        squares.insert(pos("c2"), Square::white(Pawn));
        // A loop to get the rook back
        squares.insert("h5".try_into().unwrap(), Square::pair(Pawn, Knight));
        squares.insert(pos("f4"), Square::pair(Pawn, Knight));
        let mut board = DenseBoard::from_squares(squares);
        board.controlling_player = PlayerColor::Black;

        // Loop the rook back to the original position
        execute_action!(board, lift, "h8");
        execute_action!(board, place, "h5");
        execute_action!(board, place, "f4");
        execute_action!(board, place, "h5");
        execute_action!(board, place, "h8");
        // White makes a move in between
        execute_action!(board, lift, "c2");
        execute_action!(board, place, "c3");
        // Black should have lost castling rights now.
        execute_action!(board, lift, "e8");

        // Queen side is allowed
        assert!(board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("c8"))));

        // King side is forbidden
        assert!(!board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("g8"))));
    }

    /// If the enemy moves your rook, you still loose castling right.
    #[test]
    fn enemy_rook_pair_move_forbids_castling() {
        use PieceType::*;

        let mut squares = HashMap::new();
        // General castling layout
        squares.insert(pos("e8"), Square::black(King));
        squares.insert("h8".try_into().unwrap(), Square::black(Rook));
        squares.insert(pos("a8"), Square::pair(Knight, Rook));
        squares.insert(pos("c7"), Square::black(Pawn));
        let mut board = DenseBoard::from_squares(squares);

        // Move the rook away
        execute_action!(board, lift, "a8");
        execute_action!(board, place, "b6");
        // Black makes a move in between
        execute_action!(board, lift, "c7");
        execute_action!(board, place, "c6");
        // Move the rook back
        execute_action!(board, lift, "b6");
        execute_action!(board, place, "a8");
        // Black should have lost castling rights now.
        execute_action!(board, lift, "e8");

        // Queen side is forbidden
        assert!(!board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("c8"))));

        // King side is allowed
        assert!(board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("g8"))));
    }

    /// Tests if the white king side castling is blocked by an owned piece.
    #[test]
    fn white_king_side_castle_blocked_piece() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(pos("e1"), Square::white(King));
        squares.insert(pos("f1"), Square::white(Bishop));
        squares.insert("h1".try_into().unwrap(), Square::white(Rook));
        let mut board = DenseBoard::from_squares(squares);
        board.castling.white_queen_side = false;

        execute_action!(board, lift, "e1");

        assert!(!board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("g1"))));
    }

    /// Tests if the white king side castling is blocked by an opponent sako.
    #[test]
    fn white_king_side_castle_blocked_sako() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(pos("e1"), Square::white(King));
        squares.insert(pos("b5"), Square::black(Bishop));
        squares.insert("h1".try_into().unwrap(), Square::white(Rook));
        let mut board = DenseBoard::from_squares(squares);
        board.castling.white_queen_side = false;

        execute_action!(board, lift, "e1");

        assert!(!board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("g1"))));
    }

    /// It is legal to castle if the rook moves across a field in Ŝako.
    /// This is only forbidden for the king.
    #[test]
    fn only_king_fields_block_castle() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(pos("e1"), Square::white(King));
        squares.insert(pos("b8"), Square::black(Rook));
        squares.insert(pos("a1"), Square::white(Rook));
        let mut board = DenseBoard::from_squares(squares);
        board.castling.white_king_side = false;

        execute_action!(board, lift, "e1");

        assert!(board
            .actions()
            .unwrap()
            .contains(&PacoAction::Place(pos("c1"))));
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

    /// Tests rollback on the initial position. I expect nothing to happen.
    /// But also, I expect nothing to crash.
    #[test]
    fn test_rollback_empty() -> Result<(), PacoError> {
        let actions = vec![];
        assert_eq!(find_last_checkpoint_index(actions.iter())?, 0);
        Ok(())
    }

    #[test]
    fn test_rollback_single_lift() -> Result<(), PacoError> {
        use PacoAction::*;
        let actions = vec![Lift(pos("d2"))];
        assert_eq!(find_last_checkpoint_index(actions.iter())?, 0);
        Ok(())
    }

    #[test]
    fn test_rollback_settled_changed() -> Result<(), PacoError> {
        use PacoAction::*;
        let actions = vec![Lift(pos("e2")), Place(pos("e4"))];
        assert_eq!(find_last_checkpoint_index(actions.iter())?, 2);
        Ok(())
    }

    /// If you end your turn with a promotion, you can rollback before you do
    /// the promotion.
    #[test]
    fn test_rollback_promotion() -> Result<(), PacoError> {
        use PacoAction::*;
        #[rustfmt::skip]
        let actions = vec![
            Lift(pos("b1")), Place(pos("c3")), Lift(pos("d7")), Place(pos("d5")),
            Lift(pos("c3")), Place(pos("d5")), Lift(pos("d5")), Place(pos("d4")),
            Lift(pos("b2")), Place(pos("b4")), Lift(pos("d4")), Place(pos("d3")),
            Lift(pos("d3")), Place(pos("b2")), Lift(pos("b2")), Place(pos("b1")),
        ];
        assert_eq!(find_last_checkpoint_index(actions.iter())?, 14);
        Ok(())
    }

    /// If you end your turn with an enemy promotion you can't roll back, even
    /// if the opponent has not done the promotion yet.
    #[test]
    fn test_rollback_promotion_opponent() -> Result<(), PacoError> {
        use PacoAction::*;
        #[rustfmt::skip]
        let actions = vec![
            Lift(pos("b1")), Place(pos("c3")), Lift(pos("d7")), Place(pos("d5")),
            Lift(pos("c3")), Place(pos("d5")), Lift(pos("h7")), Place(pos("h6")),
            Lift(pos("d5")), Place(pos("c3")), Lift(pos("h6")), Place(pos("h5")),
            Lift(pos("c3")), Place(pos("b1")),
        ];
        assert_eq!(find_last_checkpoint_index(actions.iter())?, 14);
        Ok(())
    }

    /// If you promote at the start of your turn, this is rolled back as well.
    #[test]
    fn test_rollback_promotion_start_turn() -> Result<(), PacoError> {
        use PacoAction::*;
        #[rustfmt::skip]
        let actions = vec![
            Lift(pos("b1")), Place(pos("c3")), Lift(pos("d7")), Place(pos("d5")),
            Lift(pos("c3")), Place(pos("d5")), Lift(pos("h7")), Place(pos("h6")),
            Lift(pos("d5")), Place(pos("c3")), Lift(pos("h6")), Place(pos("h5")),
            Lift(pos("c3")), Place(pos("b1")), Promote(PieceType::Queen), Lift(pos("h5")),
        ];
        assert_eq!(find_last_checkpoint_index(actions.iter())?, 14);
        Ok(())
    }

    /// If you end your turn with a promotion and also unite with the king in
    /// the same action, then this can't be rolled back.
    #[test]
    fn test_rollback_promotion_king_union() -> Result<(), PacoError> {
        use PacoAction::*;
        #[rustfmt::skip]
        let actions = vec![
            Lift(pos("f2")), Place(pos("f4")), Lift(pos("f7")), Place(pos("f5")),
            Lift(pos("g2")), Place(pos("g4")), Lift(pos("f5")), Place(pos("g4")),
            Lift(pos("f4")), Place(pos("f5")), Lift(pos("a7")), Place(pos("a6")),
            Lift(pos("f5")), Place(pos("f6")), Lift(pos("a6")), Place(pos("a5")),
            Lift(pos("f6")), Place(pos("f7")), Lift(pos("a5")), Place(pos("a4")),
            Lift(pos("f7")), Place(pos("e8")),
        ];
        assert_eq!(find_last_checkpoint_index(actions.iter())?, 22);
        Ok(())
    }

    /// Checks that uniting with the king sets the game state to Victory.
    /// Also checks that it remains running on all the preceding moves, which
    /// incudes another union.
    #[test]
    fn test_white_victory_after_pacosako() -> Result<(), PacoError> {
        let mut board = DenseBoard::new();
        assert_eq!(board.victory_state(), VictoryState::Running);

        execute_action!(board, lift, "e2");
        execute_action!(board, place, "e4");
        assert_eq!(board.victory_state(), VictoryState::Running);

        execute_action!(board, lift, "d7");
        execute_action!(board, place, "d5");
        assert_eq!(board.victory_state(), VictoryState::Running);

        execute_action!(board, lift, "f1");
        execute_action!(board, place, "b5");
        assert_eq!(board.victory_state(), VictoryState::Running);

        // Here we unite, but we don't unite with a king.
        execute_action!(board, lift, "d5");
        execute_action!(board, place, "e4");
        assert_eq!(board.victory_state(), VictoryState::Running);

        // Now we unite with the black king.
        execute_action!(board, lift, "b5");
        execute_action!(board, place, "e8");
        assert_eq!(
            board.victory_state(),
            VictoryState::PacoVictory(PlayerColor::White)
        );

        assert!(board.actions()?.is_empty());

        Ok(())
    }

    #[test]
    fn test_black_victory_after_pacosako() -> Result<(), PacoError> {
        let mut board = DenseBoard::new();
        assert_eq!(board.victory_state(), VictoryState::Running);

        execute_action!(board, lift, "e2");
        execute_action!(board, place, "e4");
        assert_eq!(board.victory_state(), VictoryState::Running);

        execute_action!(board, lift, "b8");
        execute_action!(board, place, "c6");
        assert_eq!(board.victory_state(), VictoryState::Running);

        execute_action!(board, lift, "e1");
        execute_action!(board, place, "e2");
        assert_eq!(board.victory_state(), VictoryState::Running);

        execute_action!(board, lift, "c6");
        execute_action!(board, place, "d4");
        assert_eq!(board.victory_state(), VictoryState::Running);

        execute_action!(board, lift, "f2");
        execute_action!(board, place, "f3");
        assert_eq!(board.victory_state(), VictoryState::Running);

        execute_action!(board, lift, "d4");
        execute_action!(board, place, "e2");
        assert_eq!(
            board.victory_state(),
            VictoryState::PacoVictory(PlayerColor::Black)
        );

        assert!(board.actions()?.is_empty());

        Ok(())
    }

    /// Tests that 50 turns without any progress result in a draw.
    /// Also tests that after those 50 turns (100 half turns) there are no
    /// longer any legal moves.
    #[test]
    fn test_no_progress_draw_after_50_moves() -> Result<(), PacoError> {
        let mut board = DenseBoard::new();

        for _ in 0..25 {
            assert_eq!(board.victory_state(), VictoryState::Running);
            // White
            execute_action!(board, lift, "b1");
            execute_action!(board, place, "c3");
            // Black
            execute_action!(board, lift, "g8");
            execute_action!(board, place, "f6");
            // White back
            execute_action!(board, lift, "c3");
            execute_action!(board, place, "b1");
            // Black back
            execute_action!(board, lift, "f6");
            execute_action!(board, place, "g8");
        }

        assert_eq!(board.victory_state(), VictoryState::NoProgressDraw);
        assert!(board.actions()?.is_empty());

        Ok(())
    }

    /// Tests that you can do more than 50 turns if you make progress.
    #[test]
    fn test_more_than_50_turns_if_there_is_progress() -> Result<(), PacoError> {
        let mut board = DenseBoard::new();

        for _ in 1..24 {
            // White
            execute_action!(board, lift, "b1");
            execute_action!(board, place, "c3");
            // Black
            execute_action!(board, lift, "g8");
            execute_action!(board, place, "f6");
            // White back
            execute_action!(board, lift, "c3");
            execute_action!(board, place, "b1");
            // Black back
            execute_action!(board, lift, "f6");
            execute_action!(board, place, "g8");
        }

        // White
        execute_action!(board, lift, "b1");
        execute_action!(board, place, "c3");
        // Black
        execute_action!(board, lift, "g8");
        execute_action!(board, place, "f6");
        // White back
        execute_action!(board, lift, "c3");
        execute_action!(board, place, "d5");
        // Black back
        execute_action!(board, lift, "f6");
        execute_action!(board, place, "d5");

        assert_eq!(board.victory_state(), VictoryState::Running);
        assert!(!board.actions()?.is_empty());

        Ok(())
    }

    #[test]
    fn test_moving_the_opponents_pawn_to_their_home_row_resets_no_progress_on_their_turn(
    ) -> Result<(), PacoError> {
        let mut board = DenseBoard::new();

        // White
        execute_action!(board, lift, "b1");
        execute_action!(board, place, "c3");
        // Black
        execute_action!(board, lift, "d7");
        execute_action!(board, place, "d5");
        // White, capture pawn
        execute_action!(board, lift, "c3");
        execute_action!(board, place, "d5");
        assert_eq!(board.no_progress_half_moves, 0);
        // Black knight
        execute_action!(board, lift, "g8");
        execute_action!(board, place, "f6");
        // White back 1
        execute_action!(board, lift, "d5");
        execute_action!(board, place, "c3");
        // Black knight back
        execute_action!(board, lift, "f6");
        execute_action!(board, place, "d5");
        // White back 1
        execute_action!(board, lift, "c3");
        execute_action!(board, place, "b1");
        assert_eq!(board.no_progress_half_moves, 4);
        execute_action!(board, promote, PieceType::Queen);
        assert_eq!(board.no_progress_half_moves, 0);

        Ok(())
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
