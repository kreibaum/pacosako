pub mod ai;
pub mod analysis;
pub mod const_tile;
pub mod draw_state;
pub mod editor;
pub mod export;
pub mod fen;
pub mod paco_action;
pub mod parser;
pub mod progress;
pub mod random;
pub mod setup_options;
mod static_include;
mod substrate;
pub mod types;
pub use crate::paco_action::PacoAction;

#[cfg(test)]
mod testdata;

use const_tile::*;
use draw_state::DrawState;
use fxhash::FxHashSet;
use paco_action::PacoActionSet;
use serde::{Deserialize, Serialize};
use setup_options::SetupOptions;
use std::cmp::{max, min};
use std::collections::hash_map::Entry;
use std::collections::HashMap;
use std::collections::HashSet;
use std::collections::VecDeque;
use std::fmt::Display;
use std::ops::Add;
use substrate::constant_bitboards::{KING_TARGETS, KNIGHT_TARGETS};
use substrate::dense::DenseSubstrate;
use substrate::{BitBoard, Substrate};
pub use types::{BoardPosition, PieceType, PlayerColor};
extern crate lazy_static;

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
    #[error("You can not 'Promote without a pawn on the opponents home row.")]
    PromoteNotAPawn,
    #[error("You need to have some free space to castle or to move the king.")]
    NoSpaceToMoveTheKing(BoardPosition),
    #[error("The input JSON is malformed.")]
    InputJsonMalformed,
    #[error("The input FEN is malformed:")]
    InputFenMalformed(String),
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
    #[error("There is no king on the board.")]
    NoKingOnBoard(PlayerColor),
    #[error("The hand is not empty when it needs to be.")]
    BoardNotSettled,
    #[error("Search is not allowed with these parameters:")]
    SearchNotAllowed(String),
    #[error("The game is over.")]
    GameIsOver,
    #[error("There are no legal actions.")]
    NoLegalActions,
}

impl From<serde_json::Error> for PacoError {
    fn from(_: serde_json::Error) -> Self {
        Self::InputJsonMalformed
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
    RepetitionDraw,
}

impl VictoryState {
    pub fn is_over(&self) -> bool {
        match self {
            VictoryState::Running => false,
            VictoryState::PacoVictory(_) => true,
            VictoryState::TimeoutVictory(_) => true,
            VictoryState::NoProgressDraw => true,
            VictoryState::RepetitionDraw => true,
        }
    }
}

pub struct VariantSettings {
    /// How often a position must a repeated to be considered a draw.
    /// 0 means that this never draws.
    pub draw_after_n_repetitions: u8,
}

/// In a DenseBoard we reserve memory for all positions.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct DenseBoard {
    pub substrate: DenseSubstrate,
    pub controlling_player: PlayerColor,
    pub required_action: RequiredAction,
    pub lifted_piece: Hand,
    /// When a pawn is moved two squares forward, the square in between is used to check en passant.
    pub en_passant: Option<BoardPosition>,
    /// When a pawn is moved on the opponents home row, you may promote it to any other piece.
    pub promotion: Option<BoardPosition>,
    /// Stores castling information
    pub castling: Castling,
    pub victory_state: VictoryState,
    pub draw_state: DrawState,
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

#[derive(Serialize, Deserialize, Clone)]
pub struct RestingPiece {
    piece_type: PieceType,
    color: PlayerColor,
    position: BoardPosition,
}

#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Castling {
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

    fn from_string(input: &str) -> Self {
        Castling {
            white_queen_side: input.contains('A'),
            white_king_side: input.contains('H'),
            black_queen_side: input.contains('a'),
            black_king_side: input.contains('h'),
        }
    }
}

impl Display for Castling {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let mut any_char = false;
        if self.white_queen_side {
            write!(f, "A")?;
            any_char = true;
        }
        if self.white_king_side {
            write!(f, "H")?;
            any_char = true;
        }
        if self.black_queen_side {
            write!(f, "a")?;
            any_char = true;
        }
        if self.black_king_side {
            write!(f, "h")?;
            any_char = true;
        }
        if !any_char {
            write!(f, "-")?;
        }
        Ok(())
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
    pub fn is_empty(&self) -> bool {
        matches!(self, Hand::Empty)
    }
    pub fn position(&self) -> Option<BoardPosition> {
        match *self {
            Hand::Empty => None,
            Hand::Single { position, .. } => Some(position),
            Hand::Pair { position, .. } => Some(position),
        }
    }
    pub fn piece(&self) -> Option<PieceType> {
        match *self {
            Hand::Empty => None,
            Hand::Single { piece, .. } => Some(piece),
            Hand::Pair { piece, .. } => Some(piece),
        }
    }
}

/// The PacoBoard trait encapsulates arbitrary Board implementations.
pub trait PacoBoard: Clone + Eq + std::hash::Hash {
    /// Check if a PacoAction is legal and execute it. Otherwise return an error.
    fn execute(&mut self, action: PacoAction) -> Result<&mut Self, PacoError>;
    /// Executes a PacoAction. This call may assume that the action is legal
    /// without checking it. Only call it when you generate the actions yourself.
    fn execute_trusted(&mut self, action: PacoAction) -> Result<&mut Self, PacoError>;
    /// List all actions that can be executed in the current state. Note that actions which leave
    /// the board in a dead-end state (like lifting up a pawn that is blocked) should be included
    /// in the list as well.
    fn actions(&self) -> Result<PacoActionSet, PacoError>;
    /// List all actions, that threaten to capture a position. This means pairs
    /// are excluded and king movement is also excluded. Movement to an empty
    /// square which could capture is included. Actions which leave the
    /// board in a dead end state are included.
    fn threat_actions(&self) -> PacoActionSet;
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
    /// Creates a new board with the current default options.
    pub fn new() -> Self {
        Self::with_options(&SetupOptions::default())
    }
    /// Creates a new board with the given options.
    pub fn with_options(options: &SetupOptions) -> Self {
        use PieceType::*;
        let mut result: Self = DenseBoard {
            substrate: DenseSubstrate::default(),
            controlling_player: PlayerColor::White,
            required_action: RequiredAction::Lift,
            lifted_piece: Hand::Empty,
            en_passant: None,
            promotion: None,
            castling: Castling::new(),
            victory_state: VictoryState::Running,
            draw_state: DrawState::with_options(options),
        };

        // Board structure
        let back_row = [Rook, Knight, Bishop, Queen, King, Bishop, Knight, Rook];
        let front_row = [Pawn; 8];

        for p in 0..8 {
            result
                .substrate
                .set_piece(PlayerColor::White, BoardPosition(p), back_row[p as usize]);
            result.substrate.set_piece(
                PlayerColor::White,
                BoardPosition(p + 8),
                front_row[p as usize],
            );
            result.substrate.set_piece(
                PlayerColor::Black,
                BoardPosition(p + 48),
                front_row[p as usize],
            );
            result.substrate.set_piece(
                PlayerColor::Black,
                BoardPosition(p + 56),
                back_row[p as usize],
            );
        }

        result
    }

    /// Creates an empty board without any figures. This is convenient to investigate
    /// simpler positions without all pieces.
    pub fn empty() -> Self {
        DenseBoard {
            substrate: DenseSubstrate::default(),
            controlling_player: PlayerColor::White,
            required_action: RequiredAction::Lift,
            lifted_piece: Hand::Empty,
            en_passant: None,
            promotion: None,
            castling: Castling::new(),
            victory_state: VictoryState::Running,
            draw_state: DrawState::default(),
        }
    }

    /// Allows you to replace the hand.
    pub fn set_hand(&mut self, new_hand: Hand) {
        self.lifted_piece = new_hand;
    }

    pub fn from_squares(squares: HashMap<BoardPosition, parser::Square>) -> Self {
        let mut result = Self::empty();
        for (&position, &square) in squares.iter() {
            result.substrate.set_square(position, square);
        }
        result
    }

    /// To help the AIs a bit, we are not allowing it to lift any pieces that
    /// get stuck instantly. They need to have at least one position where they
    /// can be placed down again.
    fn pieces_that_can_be_lifted(&self) -> Result<PacoActionSet, PacoError> {
        let mut result = BitBoard::default();

        for p in self.substrate.bitboard_color(self.controlling_player) {
            let is_pair = self.substrate.has_piece(self.controlling_player.other(), p);
            let piece = self.substrate.get_piece(self.controlling_player, p);
            if let Some(piece) = piece {
                // For the King we need a special case, otherwise we would be
                // checking castling options which is expensive.
                // Since a castling option implies a move option, there is no
                // need to check for castling options.
                if piece == PieceType::King {
                    let targets = self.place_targets_king_without_castling(p);
                    if !targets.is_empty() {
                        result.insert(p);
                    }
                } else {
                    let targets = self.place_targets(p, piece, is_pair)?;
                    if !targets.is_empty() {
                        result.insert(p);
                    }
                }
            }
        }

        Ok(PacoActionSet::LiftSet(result))
    }

    /// Lifts the piece of the current player in the given position of the board.
    /// Only one piece may be lifted at a time.
    fn lift(&mut self, position: BoardPosition) -> Result<&mut Self, PacoError> {
        if self.required_action != RequiredAction::Lift {
            return Err(PacoError::LiftingWhenNotAllowed(self.required_action));
        }

        if self.lifted_piece != Hand::Empty {
            return Err(PacoError::LiftFullHand);
        }
        // Lifting is always followed by a place.
        self.required_action = RequiredAction::Place;
        // Lifting already increases the "no progress" counter. If we do it at
        // the end of the move, then in-chain promotions are a problem.
        self.draw_state.half_move_with_no_progress();
        // We unwrap the pieces once to remove the outer Some() from the .get_mut(..) call.
        // We still receive an optional where None represents an empty square.
        let piece = self.substrate.get_piece(self.controlling_player, position);
        let partner = self
            .substrate
            .get_piece(self.controlling_player.other(), position);

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
                self.substrate
                    .remove_piece(self.controlling_player.other(), position);
            } else {
                self.lifted_piece = Hand::Single {
                    piece: piece_type,
                    position,
                };
            }
            self.substrate
                .remove_piece(self.controlling_player, position);
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
                    self.en_passant = None;
                    return self.place_king(position, target);
                }

                // Read piece currently on the board at the target position
                // and place the held piece there.
                let board_piece = self.substrate.get_piece(self.controlling_player, target);
                self.substrate
                    .set_piece(self.controlling_player, target, piece);

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

                    let new_partner = self
                        .substrate
                        .get_piece(self.controlling_player.other(), target);

                    // Check if the half move counter gets reset.
                    // Is there a new union we are creating?
                    if new_partner.is_some() {
                        self.draw_state.reset_half_move_counter();
                    }

                    self.en_passant = None;
                    self.check_and_mark_en_passant(piece, position, target);

                    self.lifted_piece = Hand::Empty;

                    // This is the only place where we need to check if we just
                    // united with the king. This is because we can safely assume
                    // that the king was not united with any other piece before.

                    if Some(PieceType::King) == new_partner {
                        // We have united with the opponent king, the game is now won.
                        self.victory_state = VictoryState::PacoVictory(self.controlling_player);
                    }

                    // Placing without chaining means the current player switches.
                    // Except for when there is still a promotion to be done.
                    if self.promotion.is_some() {
                        self.required_action = RequiredAction::PromoteThenFinish;
                    } else {
                        self.required_action = RequiredAction::Lift;
                        self.controlling_player = self.controlling_player.other();
                        draw_state::record_position(self);
                    }
                }
                Ok(self)
            }
            Hand::Pair {
                piece,
                partner,
                position,
            } => {
                if !self.substrate.is_empty(target) {
                    Err(PacoError::PlacePairFullPosition)
                } else {
                    self.en_passant = None;
                    self.check_and_mark_en_passant(piece, position, target);

                    self.substrate
                        .set_piece(self.controlling_player, target, piece);
                    self.substrate
                        .set_piece(self.controlling_player.other(), target, partner);
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
                        draw_state::record_position(self);
                    }

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
            self.en_passant = Some(position.advance_pawn(self.controlling_player).unwrap());
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
            && self.en_passant == Some(target_square)
            // And if the pawn is actually capturing, and not just chaining out
            // of a pair into the empty en passant square.
            && source_square.advance_pawn(self.controlling_player) != Some(target_square)
    }

    // Swaps the content of two squares. Does not touch lifted pieces.
    // Usually done for auxiliary movement like en passant or castling.
    fn swap(&mut self, pos1: BoardPosition, pos2: BoardPosition) {
        self.substrate.swap(pos1, pos2);
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
        if let Some((rook_source, rook_target)) =
            get_castling_auxiliary_move(king_source, king_target)
        {
            self.ensure_board_clean(king_source, king_target)?;

            // Swap rooks
            self.swap(rook_source, rook_target);
        }

        // Place down the king
        self.substrate
            .set_piece(self.controlling_player, king_target, PieceType::King);
        self.lifted_piece = Hand::Empty;

        // Forfeit castling rights.
        self.castling
            .remove_rights_for_color(self.controlling_player);
        self.controlling_player = self.controlling_player.other();
        self.required_action = RequiredAction::Lift;

        // Moving the king does never progress the game and even
        // castling or forfeiting castling does not count as
        // progress according to FIDE rules.
        draw_state::record_position(self);
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
            if !self.substrate.is_empty(BoardPosition(i)) {
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
            let owner = target
                .home_row()
                .expect("Promotion target outside home row")
                .other();
            assert_eq!(self.controlling_player, owner);

            // Safety check that there really is a pawn in the target position.
            if self.substrate.get_piece(owner, target) != Some(PieceType::Pawn) {
                return Err(PacoError::PromoteNotAPawn);
            }
            self.substrate.set_piece(owner, target, new_type);
            self.promotion = None;

            // Promotion counts as progress.
            self.draw_state.reset_half_move_counter();

            match self.required_action {
                RequiredAction::PromoteThenLift => {
                    self.required_action = RequiredAction::Lift;
                    draw_state::record_position(self);
                }
                RequiredAction::Lift => {
                    return Err(PacoError::PromotingWhenNotAllowed(RequiredAction::Lift))
                }
                RequiredAction::Place => {
                    return Err(PacoError::PromotingWhenNotAllowed(RequiredAction::Place))
                }
                RequiredAction::PromoteThenPlace => {
                    self.required_action = RequiredAction::Place;
                }
                RequiredAction::PromoteThenFinish => {
                    self.required_action = RequiredAction::Lift;
                    self.controlling_player = self.controlling_player.other();
                    self.en_passant = None;
                    draw_state::record_position(self);
                }
            }

            Ok(self)
        } else {
            Err(PacoError::PromoteWithoutCandidate)
        }
    }

    /// All place target for a piece of given type at a given position.
    /// This is intended to receive its own lifted piece as input but will work if the
    /// input piece is different.
    fn place_targets(
        &self,
        position: BoardPosition,
        piece_type: PieceType,
        is_pair: bool,
    ) -> Result<BitBoard, PacoError> {
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

    fn threat_place_targets(&self, position: BoardPosition, piece_type: PieceType) -> BitBoard {
        use PieceType::*;
        match piece_type {
            Pawn => self.threat_place_targets_pawn(position),
            Rook => self.place_targets_rock(position, false, true),
            Knight => self.place_targets_knight(position, false, true),
            Bishop => self.place_targets_bishop(position, false, true),
            Queen => self.place_targets_queen(position, false, true),
            King => BitBoard::default(), // The king can not threaten.
        }
    }

    /// Calculates all possible placement targets for a pawn at the given position.
    fn place_targets_pawn(&self, position: BoardPosition, is_pair: bool) -> BitBoard {
        use PlayerColor::White;
        let mut possible_moves = BitBoard::default();

        let forward = self.controlling_player.forward_direction();

        // Striking left & right, this is only possible if there is a target
        // and in particular this is never possible for a pair.
        if !is_pair {
            let strike_directions = [(-1, forward), (1, forward)];
            let en_passant_square = self.en_passant;
            strike_directions
                .iter()
                .filter_map(|d| position.add(*d))
                .filter(|p| {
                    self.substrate
                        .has_piece(self.controlling_player.other(), *p)
                        || en_passant_square == Some(*p)
                })
                .for_each(|p| {
                    possible_moves.insert(p);
                });
        }

        // Moving forward, this is similar to a king
        if let Some(step) = position.add((0, forward)) {
            if self.substrate.is_empty(step) {
                possible_moves.insert(step);
                // If we are on the base row or further back, check if we can move another step.
                let double_move_allowed = if self.controlling_player == White {
                    position.y() <= 1
                } else {
                    position.y() >= 6
                };
                if double_move_allowed {
                    if let Some(step_2) = step.add((0, forward)) {
                        if self.substrate.is_empty(step_2) {
                            possible_moves.insert(step_2);
                        }
                    }
                }
            }
        }

        possible_moves
    }
    /// Calculates all possible threat placement targets for a pawn at the given
    /// position.
    fn threat_place_targets_pawn(&self, position: BoardPosition) -> BitBoard {
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
    ) -> BitBoard {
        let mut result = BitBoard::default();
        let directions = [(1, 0), (0, 1), (-1, 0), (0, -1)];

        for d in directions {
            result.insert_all(self.slide_targets(position, d, is_pair, is_threat_detection));
        }

        result
    }

    /// Calculates all possible placement targets for a knight at the given position.
    fn place_targets_knight(
        &self,
        position: BoardPosition,
        is_pair: bool,
        is_threat_detection: bool,
    ) -> BitBoard {
        let targets_on_board = KNIGHT_TARGETS[position.0 as usize];

        if is_threat_detection {
            targets_on_board
        } else if is_pair {
            targets_on_board
                .iter()
                .filter(|p| self.substrate.is_empty(*p))
                .collect()
        } else {
            targets_on_board
                .iter()
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
    ) -> BitBoard {
        let mut result = BitBoard::default();
        let directions = [(1, 1), (-1, 1), (1, -1), (-1, -1)];

        for d in directions {
            result.insert_all(self.slide_targets(position, d, is_pair, is_threat_detection));
        }

        result
    }
    /// Calculates all possible placement targets for a queen at the given position.
    fn place_targets_queen(
        &self,
        position: BoardPosition,
        is_pair: bool,
        is_threat_detection: bool,
    ) -> BitBoard {
        let mut result = BitBoard::default();
        let directions = [
            (0, 1),
            (1, 1),
            (1, 0),
            (1, -1),
            (0, -1),
            (-1, -1),
            (-1, 0),
            (-1, 1),
        ];

        for d in directions {
            result.insert_all(self.slide_targets(position, d, is_pair, is_threat_detection));
        }

        result
    }

    /// Calculates all possible placement targets for a king at the given position.
    fn place_targets_king(&self, position: BoardPosition) -> Result<BitBoard, PacoError> {
        let mut targets_on_board = self.place_targets_king_without_castling(position);

        // Threat computation is expensive so we need to make sure we only do it once.
        let mut lazy_threats: Option<[IsThreatened; 64]> = None;
        let calc_threats = || {
            // TODO: This should utilize a modified amazon algorithm as a first step.
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
            if self.substrate.is_empty(B1)
                && self.substrate.is_empty(C1)
                && self.substrate.is_empty(D1)
            {
                // Check that there are no threats
                if lazy_threats.is_none() {
                    lazy_threats = Some(calc_threats()?);
                }
                let threats = lazy_threats.unwrap();
                if !threats[2].0 && !threats[3].0 && !threats[4].0 {
                    targets_on_board.insert(C1);
                }
            }
        }
        if self.controlling_player == PlayerColor::White && self.castling.white_king_side {
            // Check if the spaces are empty
            if self.substrate.is_empty(F1) && self.substrate.is_empty(G1) {
                // Check that there are no threats
                if lazy_threats.is_none() {
                    lazy_threats = Some(calc_threats()?);
                }
                let threats = lazy_threats.unwrap();
                if !threats[4].0 && !threats[5].0 && !threats[6].0 {
                    targets_on_board.insert(G1);
                }
            }
        }
        if self.controlling_player == PlayerColor::Black && self.castling.black_queen_side {
            // Check if the spaces are empty
            if self.substrate.is_empty(B8)
                && self.substrate.is_empty(C8)
                && self.substrate.is_empty(D8)
            {
                // Check that there are no threats
                if lazy_threats.is_none() {
                    lazy_threats = Some(calc_threats()?);
                }
                let threats = lazy_threats.unwrap();
                if !threats[58].0 && !threats[59].0 && !threats[60].0 {
                    targets_on_board.insert(C8);
                }
            }
        }
        if self.controlling_player == PlayerColor::Black && self.castling.black_king_side {
            // Check if the spaces are empty
            if self.substrate.is_empty(F8) && self.substrate.is_empty(G8) {
                // Check that there are no threats
                if lazy_threats.is_none() {
                    lazy_threats = Some(calc_threats()?);
                }
                let threats = lazy_threats.unwrap();
                if !threats[60].0 && !threats[61].0 && !threats[62].0 {
                    targets_on_board.insert(G8);
                }
            }
        }

        Ok(targets_on_board)
    }

    fn place_targets_king_without_castling(&self, position: BoardPosition) -> BitBoard {
        KING_TARGETS[position.0 as usize]
            .iter()
            // Placing the king works like placing a pair, as he can only be
            // placed on empty squares.
            .filter(|p| self.substrate.is_empty(*p))
            .collect()
    }

    /// Decide whether the current player may place a single lifted piece at the indicated position.
    ///
    /// This is only forbidden when the target position holds a piece of the own color
    /// without a dance partner.
    fn can_place_single_at(&self, target: BoardPosition) -> bool {
        self.substrate
            .has_piece(self.controlling_player.other(), target)
            || !self.substrate.has_piece(self.controlling_player, target)
    }

    /// Calculates all targets by sliding step by step in a given direction and stopping at the
    /// first obstacle or at the end of the board.
    fn slide_targets(
        &self,
        start: BoardPosition,
        (dx, dy): (i8, i8),
        is_pair: bool,
        is_threat_detection: bool,
    ) -> BitBoard {
        let mut possible_moves = BitBoard::default();
        let mut slide = start.add((dx, dy));

        // This while loop leaves if we drop off the board or if we hit a target.
        // The is_pair parameter determines, if the first thing we hit is a valid target.
        while let Some(target) = slide {
            if self.substrate.is_empty(target) {
                possible_moves.insert(target);
                slide = target.add((dx, dy));
            } else if !is_pair && self.can_place_single_at(target) {
                possible_moves.insert(target);
                slide = None;
            } else {
                // If we are only interested in determining threats, then we
                // also count a square with a single own piece as threatened.
                if is_threat_detection {
                    possible_moves.insert(target);
                }
                slide = None;
            }
        }
        possible_moves
    }

    fn place_actions(&self) -> Result<PacoActionSet, PacoError> {
        match self.lifted_piece {
            Hand::Empty => {
                // This should never be called. You can't place without having
                // a piece in hand.
                Err(PacoError::PlaceEmptyHand)
            }
            Hand::Single { piece, position } => {
                // the player currently lifts a piece, we calculate all possible positions where
                // it can be placed down. This takes opponents pieces in considerations but won't
                // discard chaining into a blocked pawn (or similar).
                Ok(PacoActionSet::PlaceSet(
                    self.place_targets(position, piece, false)?,
                ))
            }
            Hand::Pair {
                piece, position, ..
            } => Ok(PacoActionSet::PlaceSet(
                self.place_targets(position, piece, true)?,
            )),
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
        if self.actions()?.contains(action) {
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
                Ok(self)
            }
            Promote(new_type) => self.promote(new_type),
        }
    }
    fn actions(&self) -> Result<PacoActionSet, PacoError> {
        // If the game is over, then there are no actions.
        if self.victory_state.is_over() {
            return Ok(PacoActionSet::default());
        }

        match self.required_action {
            RequiredAction::Lift => self.pieces_that_can_be_lifted(),
            RequiredAction::Place => self.place_actions(),
            RequiredAction::PromoteThenLift => Ok(PacoActionSet::all_promotion_options()),
            RequiredAction::PromoteThenPlace => Ok(PacoActionSet::all_promotion_options()),
            RequiredAction::PromoteThenFinish => Ok(PacoActionSet::all_promotion_options()),
        }
    }
    fn threat_actions(&self) -> PacoActionSet {
        // Promotion can threaten, because it can be done as part of a chain.
        if self.promotion.is_some() {
            return PacoActionSet::all_promotion_options();
        }

        match self.lifted_piece {
            Hand::Empty => {
                // If no piece is lifted up, then we just return lifting actions
                // of all pieces of the current player. We need to filter out
                // the king, as the king can never threaten.
                // # Rules 2017: "A king cannot be united with another piece and
                // # is therefore exempt from creating, moving or taking over a
                // # union and from the chain reaction."
                PacoActionSet::LiftSet(
                    self.substrate
                        .bitboard_color(self.controlling_player)
                        .iter()
                        .filter(|position| {
                            self.substrate.get_piece(self.controlling_player, *position)
                                != Some(PieceType::King)
                        })
                        .collect(),
                )
            }
            Hand::Single { piece, position } => {
                // The player currently holds a piece, we calculate all possible positions where
                // it can be placed down. This takes opponents pieces in considerations but won't
                // discard chaining into a blocked pawn (or similar).
                PacoActionSet::PlaceSet(self.threat_place_targets(position, piece))
            }
            Hand::Pair { .. } => PacoActionSet::default(),
        }
    }
    fn is_settled(&self) -> bool {
        self.lifted_piece == Hand::Empty
    }
    fn controlling_player(&self) -> PlayerColor {
        self.controlling_player
    }
    fn get_at(&self, position: BoardPosition) -> (Option<PieceType>, Option<PieceType>) {
        (
            self.substrate.get_piece(PlayerColor::White, position),
            self.substrate.get_piece(PlayerColor::Black, position),
        )
    }
    fn en_passant_capture_possible(&self) -> bool {
        if let Hand::Single {
            piece: PieceType::Pawn,
            position,
        } = self.lifted_piece
        {
            if let Some(target_position) = self.en_passant {
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
    fn king_in_union(&self, color: PlayerColor) -> bool {
        match self.substrate.find_king(color) {
            Ok(king_pos) => self.substrate.has_piece(color.other(), king_pos),
            // If there is no king, then it is not in a union.
            Err(_) => false,
        }
    }
}

impl Default for DenseBoard {
    fn default() -> Self {
        Self::new()
    }
}

pub struct ExploredState<T: PacoBoard> {
    pub settled: HashSet<T>,
    pub found_via: HashMap<T, Vec<(PacoAction, Option<T>)>>,
}

/// Defines an algorithm that determines all moves.
/// A move is a sequence of legal actions Lift(p1), Place(p2), Place(p3), ..
/// which ends with an empty hand.
///
/// Essentially I am investigating a finite, possibly cyclic, directed graph where some nodes
/// are marked (settled boards) and I wish to find all acyclic paths from the root to these
/// marked (settled) nodes.
pub fn determine_all_moves<T: PacoBoard>(board: T) -> Result<ExploredState<T>, PacoError> {
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
                    if b.controlling_player() != board.controlling_player()
                        || b.victory_state().is_over()
                    {
                        // The controlling player has switched,
                        // we don't look at the following moves.
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
pub fn trace_first_move<T: PacoBoard, S: std::hash::BuildHasher>(
    target: &T,
    found_via: &HashMap<T, Vec<(PacoAction, Option<T>)>, S>,
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
    let mut seen: FxHashSet<T> = FxHashSet::default();
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
    use crate::analysis::is_sako;

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
        assert_eq!(pos("d3"), board.en_passant.unwrap());
        assert!(board.actions().unwrap().contains(PacoAction::Place(D3)));

        // Execute en passant union
        execute_action!(board, place, "d3");

        // Check if the target pawn was indeed united.
        assert_eq!(
            board.substrate.get_piece(PlayerColor::White, D3),
            Some(Pawn)
        );
    }

    /// This test sets up a situation where a sako through a chain is possible using en passant.
    #[test]
    fn en_passant_chain_sako() {
        use PieceType::*;

        // Setup a situation where en passant can happen.
        let mut squares = HashMap::new();
        squares.insert(pos("c4"), Square::black(Pawn));
        squares.insert(pos("d2"), Square::pair(Pawn, Knight));
        squares.insert(E1, Square::white(King));
        let mut board = DenseBoard::from_squares(squares);

        execute_action!(board, lift, "d2");
        execute_action!(board, place, "d4");

        assert_eq!(pos("d3"), board.en_passant.unwrap());

        let sako_states = find_sako_states(board).unwrap();

        assert_eq!(sako_states.len(), 1);
    }

    /// Simple test that moves a pawn onto the opponents home row and checks promotion options.
    #[test]
    fn promote_pawn() {
        use PieceType::*;
        use PlayerColor::*;

        let mut squares = HashMap::new();
        squares.insert(C7, Square::white(Pawn));
        let mut board = DenseBoard::from_squares(squares);

        execute_action!(board, lift, "c7");
        execute_action!(board, place, "c8");

        assert_eq!(board.promotion, Some(C8));
        assert_eq!(board.controlling_player(), White);
        assert_eq!(board.required_action, RequiredAction::PromoteThenFinish);
        let options: Vec<_> = board.actions().unwrap().iter().collect();
        assert_eq!(
            options,
            vec![
                PacoAction::Promote(PieceType::Rook),
                PacoAction::Promote(PieceType::Knight),
                PacoAction::Promote(PieceType::Bishop),
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
        squares.insert(D6, Square::black(King));
        squares.insert(D7, Square::white(Pawn));
        squares.insert(E8, Square::pair(Bishop, Pawn));
        squares.insert(F7, Square::pair(Bishop, Pawn));

        let board = DenseBoard::from_squares(squares);

        let sako_states = find_sako_states(board).unwrap();

        assert_eq!(sako_states.len(), 1);
    }

    /// Checks that en_passant information is correctly recorded.
    #[test]
    fn test_en_passant_information() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(C2, Square::white(Pawn));
        squares.insert(C7, Square::black(Pawn));
        squares.insert(E2, Square::pair(Pawn, Pawn));
        squares.insert(E7, Square::pair(Pawn, Pawn));
        let mut board = DenseBoard::from_squares(squares);

        // Check that white can be captured en passant
        execute_action!(board, lift, "c2");
        execute_action!(board, place, "c4");

        assert_eq!(C3, board.en_passant.unwrap());

        // Check that white can be captured en passant
        execute_action!(board, lift, "c7");
        execute_action!(board, place, "c5");

        assert_eq!(C6, board.en_passant.unwrap());

        // Check that white can be captured en passant when they move a pair
        execute_action!(board, lift, "e2");
        execute_action!(board, place, "e4");

        assert_eq!(E3, board.en_passant.unwrap());

        // Check that black can be captured en passant when they move a pair
        execute_action!(board, lift, "e7");
        execute_action!(board, place, "e5");

        assert_eq!(E6, board.en_passant.unwrap());
    }

    /// Checks that en_passant information is correctly recorded.
    #[test]
    fn test_en_passant_information_decays() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(C5, Square::white(Pawn));
        squares.insert(D5, Square::white(Pawn));
        squares.insert(E7, Square::black(Pawn));
        squares.insert(F7, Square::black(Pawn));
        let mut board = DenseBoard::from_squares(squares);
        board.controlling_player = PlayerColor::Black;

        // Black moves, this marks e6 as en passant
        execute_action!(board, lift, "e7");
        execute_action!(board, place, "e5");

        assert_eq!(pos("e6"), board.en_passant.unwrap());

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
    #[allow(clippy::needless_range_loop)] // Looks a lot nicer this way
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
        squares.insert(H8, Square::pair(Knight, Pawn));
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
    fn test_threat_en_passant() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(pos("e5"), Square::white(Pawn));
        squares.insert(pos("f7"), Square::pair(Pawn, Pawn));
        let mut board = DenseBoard::from_squares(squares);
        board.controlling_player = PlayerColor::Black;

        execute_action!(board, lift, "f7");
        execute_action!(board, place, "f5");

        assert_eq!(pos("f6"), board.en_passant.unwrap());

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
        squares.insert(E1, Square::white(King));
        squares.insert(H1, Square::white(Rook));
        squares.insert(A1, Square::white(Rook));
        let mut board = DenseBoard::from_squares(squares);

        execute_action!(board, lift, "e1");
        // Queen side
        assert!(board.actions().unwrap().contains(PacoAction::Place(C1)));

        // King side
        assert!(board.actions().unwrap().contains(PacoAction::Place(G1)));

        // Moving the king also moves the rook
        execute_action!(board, place, "c1");
        assert_eq!(Some(PieceType::Rook), board.get_at(D1).0);
    }

    /// Checks that white castling kingside move the rook and the united black piece.
    #[test]
    fn white_king_castle_moves_rook() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(E1, Square::white(King));
        squares.insert(H1, Square::pair(Rook, Knight));
        let mut board = DenseBoard::from_squares(squares);
        execute_action!(board, lift, "e1");
        execute_action!(board, place, "g1");
        assert_eq!(Some(PieceType::Rook), board.get_at(F1).0);
        assert_eq!(Some(PieceType::Knight), board.get_at(F1).1);
    }

    /// Tests if the white king moving forfeits castling rights.
    #[test]
    fn white_king_forfeit_castle() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(E1, Square::white(King));
        squares.insert(H1, Square::white(Rook));
        squares.insert(A1, Square::white(Rook));
        squares.insert(C7, Square::black(Pawn));
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
        assert!(!board.actions().unwrap().contains(PacoAction::Place(C1)));

        // King side
        assert!(!board.actions().unwrap().contains(PacoAction::Place(G1)));
    }

    /// Tests if the white queen rook moving forfeits castling rights.
    #[test]
    fn white_queen_rook_forfeit_castle() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(E1, Square::white(King));
        squares.insert(H1, Square::white(Rook));
        squares.insert(A1, Square::white(Rook));
        squares.insert(C7, Square::black(Pawn));
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
        assert!(!board.actions().unwrap().contains(PacoAction::Place(C1)));

        // King side should be allowed
        assert!(board.actions().unwrap().contains(PacoAction::Place(G1)));
    }

    /// Tests if the white king rook moving forfeits castling rights.
    #[test]
    fn white_king_rook_forfeit_castle() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(E1, Square::white(King));
        squares.insert(H1, Square::white(Rook));
        squares.insert(A1, Square::white(Rook));
        squares.insert(C7, Square::black(Pawn));
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
        assert!(board.actions().unwrap().contains(PacoAction::Place(C1)));

        // King side should be forbidden
        assert!(!board.actions().unwrap().contains(PacoAction::Place(G1)));
    }

    /// Tests if the black king castling is provided as an action when lifting the king.
    #[test]
    fn black_castle() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(E8, Square::black(King));
        squares.insert(H8, Square::black(Rook));
        squares.insert(A8, Square::black(Rook));
        let mut board = DenseBoard::from_squares(squares);
        board.controlling_player = PlayerColor::Black;

        execute_action!(board, lift, "e8");
        // Queen side
        assert!(board.actions().unwrap().contains(PacoAction::Place(C8)));

        // King side
        assert!(board.actions().unwrap().contains(PacoAction::Place(G8)));

        // Moving the king also moves the rook
        execute_action!(board, place, "c8");
        assert_eq!(Some(PieceType::Rook), board.get_at(D8).1);
    }

    /// Checks that black castling kingside move the rook and the united white piece.
    #[test]
    fn black_king_castle_moves_rook() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(E8, Square::black(King));
        squares.insert(H8, Square::pair(Knight, Rook));
        let mut board = DenseBoard::from_squares(squares);
        board.controlling_player = PlayerColor::Black;

        execute_action!(board, lift, "e8");
        execute_action!(board, place, "g8");
        assert_eq!(Some(PieceType::Knight), board.get_at(F8).0);
        assert_eq!(Some(PieceType::Rook), board.get_at(F8).1);
    }

    /// Tests if the black king moving forfeits castling rights.
    #[test]
    fn black_king_forfeit_castle() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(E8, Square::black(King));
        squares.insert(H8, Square::black(Rook));
        squares.insert(A8, Square::black(Rook));
        squares.insert(C2, Square::white(Pawn));
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
        assert!(!board.actions().unwrap().contains(PacoAction::Place(C8)));

        // King side
        assert!(!board.actions().unwrap().contains(PacoAction::Place(G8)));
    }

    /// Tests if the black queen side rook moving forfeits castling rights.
    #[test]
    fn black_queen_rook_forfeit_castle() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(E8, Square::black(King));
        squares.insert(H8, Square::black(Rook));
        squares.insert(A8, Square::black(Rook));
        squares.insert(C2, Square::white(Pawn));
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
        assert!(!board.actions().unwrap().contains(PacoAction::Place(C8)));

        // King side is allowed
        assert!(board.actions().unwrap().contains(PacoAction::Place(G8)));
    }

    /// You can do a chain where the rook ends up in the original position.
    /// This still forfeits the castling right.
    #[test]
    fn idempotent_chain_forfeits_castle() {
        use PieceType::*;

        let mut squares = HashMap::new();
        // General castling layout
        squares.insert(E8, Square::black(King));
        squares.insert(H8, Square::black(Rook));
        squares.insert(A8, Square::black(Rook));
        squares.insert(C2, Square::white(Pawn));
        // A loop to get the rook back
        squares.insert(H5, Square::pair(Pawn, Knight));
        squares.insert(F4, Square::pair(Pawn, Knight));
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
        assert!(board.actions().unwrap().contains(PacoAction::Place(C8)));

        // King side is forbidden
        assert!(!board.actions().unwrap().contains(PacoAction::Place(G8)));
    }

    /// If the enemy moves your rook, you still loose castling right.
    #[test]
    fn enemy_rook_pair_move_forbids_castling() {
        use PieceType::*;

        let mut squares = HashMap::new();
        // General castling layout
        squares.insert(E8, Square::black(King));
        squares.insert(H8, Square::black(Rook));
        squares.insert(A8, Square::pair(Knight, Rook));
        squares.insert(C7, Square::black(Pawn));
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
        assert!(!board.actions().unwrap().contains(PacoAction::Place(C8)));

        // King side is allowed
        assert!(board.actions().unwrap().contains(PacoAction::Place(G8)));
    }

    /// Tests if the white king side castling is blocked by an owned piece.
    #[test]
    fn white_king_side_castle_blocked_piece() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(E1, Square::white(King));
        squares.insert(F1, Square::white(Bishop));
        squares.insert(H1, Square::white(Rook));
        let mut board = DenseBoard::from_squares(squares);
        board.castling.white_queen_side = false;

        execute_action!(board, lift, "e1");

        assert!(!board.actions().unwrap().contains(PacoAction::Place(G1)));
    }

    /// Tests if the white king side castling is blocked by an opponent sako.
    #[test]
    fn white_king_side_castle_blocked_sako() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(E1, Square::white(King));
        squares.insert(B5, Square::black(Bishop));
        squares.insert(H1, Square::white(Rook));
        let mut board = DenseBoard::from_squares(squares);
        board.castling.white_queen_side = false;

        execute_action!(board, lift, "e1");

        assert!(!board
            .actions()
            .unwrap()
            .contains(PacoAction::Place(pos("g1"))));
    }

    /// It is legal to castle if the rook moves across a field in Ŝako.
    /// This is only forbidden for the king.
    #[test]
    fn only_king_fields_block_castle() {
        use PieceType::*;

        let mut squares = HashMap::new();
        squares.insert(E1, Square::white(King));
        squares.insert(pos("b8"), Square::black(Rook));
        squares.insert(pos("a1"), Square::white(Rook));
        let mut board = DenseBoard::from_squares(squares);
        board.castling.white_king_side = false;

        execute_action!(board, lift, "e1");

        assert!(board
            .actions()
            .unwrap()
            .contains(PacoAction::Place(pos("c1"))));
    }

    /// Tests rollback on the initial position. I expect nothing to happen.
    /// But also, I expect nothing to crash.
    #[test]
    fn test_rollback_empty() -> Result<(), PacoError> {
        let actions = [];
        assert_eq!(find_last_checkpoint_index(actions.iter())?, 0);
        Ok(())
    }

    #[test]
    fn test_rollback_single_lift() -> Result<(), PacoError> {
        use PacoAction::*;
        let actions = [Lift(pos("d2"))];
        assert_eq!(find_last_checkpoint_index(actions.iter())?, 0);
        Ok(())
    }

    #[test]
    fn test_rollback_settled_changed() -> Result<(), PacoError> {
        use PacoAction::*;
        let actions = [Lift(pos("e2")), Place(pos("e4"))];
        assert_eq!(find_last_checkpoint_index(actions.iter())?, 2);
        Ok(())
    }

    /// If you end your turn with a promotion, you can rollback before you do
    /// the promotion.
    #[test]
    fn test_rollback_promotion() -> Result<(), PacoError> {
        use PacoAction::*;
        #[rustfmt::skip]
        let actions = [Lift(pos("b1")), Place(pos("c3")), Lift(pos("d7")), Place(pos("d5")),
            Lift(pos("c3")), Place(pos("d5")), Lift(pos("d5")), Place(pos("d4")),
            Lift(pos("b2")), Place(pos("b4")), Lift(pos("d4")), Place(pos("d3")),
            Lift(pos("d3")), Place(pos("b2")), Lift(pos("b2")), Place(pos("b1"))];
        assert_eq!(find_last_checkpoint_index(actions.iter())?, 14);
        Ok(())
    }

    /// If you end your turn with an enemy promotion you can't roll back, even
    /// if the opponent has not done the promotion yet.
    #[test]
    fn test_rollback_promotion_opponent() -> Result<(), PacoError> {
        use PacoAction::*;
        #[rustfmt::skip]
        let actions = [Lift(pos("b1")), Place(pos("c3")), Lift(pos("d7")), Place(pos("d5")),
            Lift(pos("c3")), Place(pos("d5")), Lift(pos("h7")), Place(pos("h6")),
            Lift(pos("d5")), Place(pos("c3")), Lift(pos("h6")), Place(pos("h5")),
            Lift(pos("c3")), Place(pos("b1"))];
        assert_eq!(find_last_checkpoint_index(actions.iter())?, 14);
        Ok(())
    }

    /// If you promote at the start of your turn, this is rolled back as well.
    #[test]
    fn test_rollback_promotion_start_turn() -> Result<(), PacoError> {
        use PacoAction::*;
        #[rustfmt::skip]
        let actions = [Lift(pos("b1")), Place(pos("c3")), Lift(pos("d7")), Place(pos("d5")),
            Lift(pos("c3")), Place(pos("d5")), Lift(pos("h7")), Place(pos("h6")),
            Lift(pos("d5")), Place(pos("c3")), Lift(pos("h6")), Place(pos("h5")),
            Lift(pos("c3")), Place(pos("b1")), Promote(PieceType::Queen), Lift(pos("h5"))];
        assert_eq!(find_last_checkpoint_index(actions.iter())?, 14);
        Ok(())
    }

    /// If you end your turn with a promotion and also unite with the king in
    /// the same action, then this can't be rolled back.
    #[test]
    fn test_rollback_promotion_king_union() -> Result<(), PacoError> {
        use PacoAction::*;
        #[rustfmt::skip]
        let actions = [Lift(pos("f2")), Place(pos("f4")), Lift(pos("f7")), Place(pos("f5")),
            Lift(pos("g2")), Place(pos("g4")), Lift(pos("f5")), Place(pos("g4")),
            Lift(pos("f4")), Place(pos("f5")), Lift(pos("a7")), Place(pos("a6")),
            Lift(pos("f5")), Place(pos("f6")), Lift(pos("a6")), Place(pos("a5")),
            Lift(pos("f6")), Place(pos("f7")), Lift(pos("a5")), Place(pos("a4")),
            Lift(pos("f7")), Place(E8)];
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
        board.draw_state.draw_after_n_repetitions = 0;

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
        board.draw_state.draw_after_n_repetitions = 0;

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
    fn test_moving_the_opponents_pawn_to_their_home_row_resets_no_progress_on_this_turn(
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
        assert_eq!(board.draw_state.no_progress_half_moves, 0);
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
        assert_eq!(board.draw_state.no_progress_half_moves, 4);
        execute_action!(board, promote, PieceType::Queen);
        assert_eq!(board.draw_state.no_progress_half_moves, 0);

        Ok(())
    }

    /// Here we check that chaining without increasing the amount of pairs does
    /// increase the no-progress counter.
    #[test]
    fn test_half_move_count_during_unproductive_chain() {
        let mut board = DenseBoard::new();

        execute_action!(board, lift, "e2");
        execute_action!(board, place, "e4");
        assert_eq!(board.draw_state.no_progress_half_moves, 1);
        execute_action!(board, lift, "d7");
        execute_action!(board, place, "d5");
        assert_eq!(board.draw_state.no_progress_half_moves, 2);
        execute_action!(board, lift, "e4");
        execute_action!(board, place, "d5");
        assert_eq!(board.draw_state.no_progress_half_moves, 0);
        execute_action!(board, lift, "e7");
        execute_action!(board, place, "e6");
        assert_eq!(board.draw_state.no_progress_half_moves, 1);
        execute_action!(board, lift, "c2");
        execute_action!(board, place, "c4");
        assert_eq!(board.draw_state.no_progress_half_moves, 2);
        execute_action!(board, lift, "e6");
        execute_action!(board, place, "d5");
        execute_action!(board, place, "d4");
        assert_eq!(board.draw_state.no_progress_half_moves, 3);
    }

    #[test]
    fn test_half_move_count_during_chain_promotion() {
        let mut board = DenseBoard::new();

        execute_action!(board, lift, "f2");
        execute_action!(board, place, "f4");
        assert_eq!(board.draw_state.no_progress_half_moves, 1);
        execute_action!(board, lift, "g7");
        execute_action!(board, place, "g5");
        assert_eq!(board.draw_state.no_progress_half_moves, 2);
        execute_action!(board, lift, "f4");
        execute_action!(board, place, "g5");
        assert_eq!(board.draw_state.no_progress_half_moves, 0);
        execute_action!(board, lift, "e7");
        execute_action!(board, place, "e5");
        assert_eq!(board.draw_state.no_progress_half_moves, 1);
        execute_action!(board, lift, "g5");
        execute_action!(board, place, "g6");
        assert_eq!(board.draw_state.no_progress_half_moves, 2);
        execute_action!(board, lift, "a7");
        execute_action!(board, place, "a5");
        assert_eq!(board.draw_state.no_progress_half_moves, 3);
        execute_action!(board, lift, "d2");
        execute_action!(board, place, "d4");
        assert_eq!(board.draw_state.no_progress_half_moves, 4);
        execute_action!(board, lift, "e5");
        execute_action!(board, place, "d4");
        assert_eq!(board.draw_state.no_progress_half_moves, 0);
        execute_action!(board, lift, "c1");
        execute_action!(board, place, "h6");
        assert_eq!(board.draw_state.no_progress_half_moves, 1);
        execute_action!(board, lift, "a5");
        execute_action!(board, place, "a4");
        assert_eq!(board.draw_state.no_progress_half_moves, 2);
        execute_action!(board, lift, "h6");
        execute_action!(board, place, "f8");
        assert_eq!(board.draw_state.no_progress_half_moves, 0);
        execute_action!(board, lift, "a8");
        execute_action!(board, place, "a5");
        assert_eq!(board.draw_state.no_progress_half_moves, 1);
        execute_action!(board, lift, "g6");
        execute_action!(board, place, "g7");
        assert_eq!(board.draw_state.no_progress_half_moves, 2);
        execute_action!(board, lift, "b8");
        execute_action!(board, place, "a6");
        assert_eq!(board.draw_state.no_progress_half_moves, 3);
        execute_action!(board, lift, "d1");
        execute_action!(board, place, "d2");
        assert_eq!(board.draw_state.no_progress_half_moves, 4);
        execute_action!(board, lift, "a5");
        execute_action!(board, place, "h5");
        assert_eq!(board.draw_state.no_progress_half_moves, 5);
        execute_action!(board, lift, "d2");
        execute_action!(board, place, "g5");
        assert_eq!(board.draw_state.no_progress_half_moves, 6);
        execute_action!(board, lift, "d8");
        execute_action!(board, place, "f6");
        assert_eq!(board.draw_state.no_progress_half_moves, 7);
        execute_action!(board, lift, "g5");
        execute_action!(board, place, "g7");
        execute_action!(board, place, "f8");
        execute_action!(board, promote, PieceType::Queen);
        execute_action!(board, place, "d6");
        assert_eq!(board.draw_state.no_progress_half_moves, 0); // This tests #52
    }

    /// A chain involving the same pawn of the opponent twice but on different
    /// squares. This is mostly a puzzle, but I wanted to be sure that it works.
    #[test]
    fn double_en_passant_chaining() {
        let mut board =
            fen::parse_fen("1lb1k3/8/1tApS3/2p2p2/1A2P1A1/1p1Ps1P1/2C1T2p/R1B1K2R w 0 AHah - -")
                .unwrap();
        assert!(!is_sako(&board, board.controlling_player).unwrap());
        execute_action!(board, lift, "c2");
        execute_action!(board, place, "c4");
        assert!(is_sako(&board, board.controlling_player).unwrap());
    }
}
