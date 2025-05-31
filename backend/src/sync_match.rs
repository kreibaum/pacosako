//! This module implements match synchronization on top of an instance manager.
//! That means when code in this module runs, the match it is running in is
//! already clear, and we only implement the Paco Ŝako specific parts.

use chrono::{DateTime, Utc};
use pacosako::variants::PieceSetupParameters;
use serde::{Deserialize, Serialize};
use serde_json::de::from_str;
use std::convert::TryFrom;

use pacosako::setup_options::SetupOptions;
use pacosako::{fen, variants, PacoAction, PacoBoard, PacoError, PlayerColor};

use crate::db::{self, Connection};
use crate::login::user::{load_user_data_for_game, PublicUserData};
use crate::login::{user, UserId};
use crate::protection::ControlLevel;
use crate::timer::{Timer, TimerConfig, TimerState};
use crate::ws::socket_auth::{SocketAuth, SocketIdentity};
use crate::ServerError;


/// Parameters required to initialize a new instance of the match.
#[derive(Deserialize, Clone)]
pub struct MatchParameters {
    timer: Option<TimerConfig>,
    safe_mode: Option<bool>,
    draw_after_n_repetitions: Option<u8>,
    pub ai_side_request: Option<AiSideRequest>,
    piece_setup: Option<PieceSetupParameters>,
}

#[derive(Deserialize, Clone)]
pub struct AiSideRequest {
    /// Color the AI should play. Color None means the AI should play randomly.
    pub color: Option<PlayerColor>,
    /// This gets looked up in `user_modelName` in the database.
    pub model_name: String,
    pub model_strength: usize,
    pub model_temperature: f32,
}

impl MatchParameters {
    /// Ensure that all values of the timer config are below 1_000_000.
    /// This ensures we don't trigger an overflow. See #85.
    pub fn sanitize(&self) -> Self {
        let timer = self.timer.clone().map(|timer| timer.sanitize());
        Self {
            timer,
            safe_mode: self.safe_mode,
            draw_after_n_repetitions: self.draw_after_n_repetitions,
            ai_side_request: self.ai_side_request.clone(),
            piece_setup: self.piece_setup,
        }
    }

    pub fn is_legal(&self) -> bool {
        let Some(timer) = &self.timer else {
            return true;
        };
        timer.is_legal()
    }
}

/// A paco sako action together with a timestamp that remembers when it was done.
/// This timestamp is important for replays.
#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct StampedAction {
    #[serde(flatten)]
    action: PacoAction,
    timestamp: DateTime<Utc>,
}

impl From<&StampedAction> for PacoAction {
    fn from(stamped_action: &StampedAction) -> Self {
        stamped_action.action
    }
}

/// A match is a recording of actions taken in it together with a unique
/// identifier that can be used to connect to the game.
/// It also takes care of tracking the timing and ensures actions are legal.
pub struct SynchronizedMatch {
    // TODO: Stop leaking private members by implementing stringify & parse in here.
    pub key: String,
    pub actions: Vec<StampedAction>,
    pub timer: Option<Timer>,
    pub setup_options: SetupOptions,
    pub white_player: Option<UserId>,
    pub black_player: Option<UserId>,
}

/// Message that may be sent by the client to the server.
#[derive(Clone, Debug, Deserialize)]
pub enum ClientMatchMessage {
    GetCurrentState { key: String },
    Subscribe { key: String },
    DoAction { key: String, action: PacoAction },
    Rollback { key: String },
    SetTimer { key: String, timer: TimerConfig },
    StartTimer { key: String },
}

impl TryFrom<&str> for ClientMatchMessage {
    type Error = &'static str;

    fn try_from(text: &str) -> Result<Self, Self::Error> {
        if let Ok(client_message) = from_str(text) {
            Ok(client_message)
        } else {
            Err("Message could not be decoded.")
        }
    }
}

async fn _load_from_db(
    key: &str,
    mut conn: db::Connection,
) -> Result<SynchronizedMatch, anyhow::Error> {
    if let Some(game) = db::game::select(key.parse()?, &mut conn).await? {
        Ok(game)
    } else {
        Err(anyhow::anyhow!("Game with key {} not found.", key))
    }
}

async fn _store_to_db(
    game: &SynchronizedMatch,
    mut conn: db::Connection,
) -> Result<(), anyhow::Error> {
    db::game::update(game, &mut conn).await?;

    Ok(())
}

/// A complete description of the match state.
/// This is currently sent to all clients whenever the game state changes.
/// As it is only a list of some actions, it should be lightweight enough
/// that sending around the whole history is not a bottleneck.
#[derive(Clone, Debug)]
pub struct CurrentMatchState {
    key: String,
    actions: Vec<StampedAction>,
    is_rollback: bool,
    pub controlling_player: PlayerColor,
    pub timer: Option<Timer>,
    pub victory_state: pacosako::VictoryState,
    pub setup_options: SetupOptions,
}

/// An extension of the current match state that contains the player metadata.
/// Only this one is actually serializable, to make sure we don't send the
/// data object missing this metadata to the client.
#[derive(Serialize, Clone, Debug)]
pub struct CurrentMatchStateClient {
    key: String,
    actions: Vec<StampedAction>,
    // We explicitly tell the client about rollbacks, because just receiving a shorter list
    // of actions can also mean the server is just lagging behind the client. This commonly
    // happens when the AI cites from the opening book, or the network is bad.
    pub is_rollback: bool,
    pub controlling_player: PlayerColor,
    pub timer: Option<Timer>,
    pub victory_state: pacosako::VictoryState,
    pub setup_options: SetupOptions,
    pub white_player: Option<PublicUserData>,
    pub black_player: Option<PublicUserData>,
    // Tells the client which pieces they are allowed to control.
    pub white_control: ControlLevel,
    pub black_control: ControlLevel,
}

/// A small version of the current match state that suffices to show a match in an overview.
#[derive(Serialize, Clone, Debug)]
pub struct CompressedMatchStateClient {
    key: String,
    current_fen: String,
    victory_state: pacosako::VictoryState,
    timer: Option<Timer>,
    white_player: Option<PublicUserData>,
    black_player: Option<PublicUserData>,
}

impl CurrentMatchState {
    /// Tries to create a new match state out of a synchronized match and an
    /// already projected board.
    fn try_new(
        sync_match: &SynchronizedMatch,
        board: &pacosako::DenseBoard,
    ) -> Result<Self, PacoError> {
        let victory_state = Self::victory_state(board, &sync_match.timer);

        Ok(Self {
            key: sync_match.key.clone(),
            actions: sync_match.actions.clone(),
            is_rollback: false,
            controlling_player: board.controlling_player(),
            timer: sync_match.timer.clone(),
            victory_state,
            setup_options: sync_match.setup_options.clone(),
        })
    }

    fn victory_state(
        board: &pacosako::DenseBoard,
        timer: &Option<Timer>,
    ) -> pacosako::VictoryState {
        if let Some(timer) = timer {
            if let TimerState::Timeout(color) = timer.get_state() {
                return pacosako::VictoryState::TimeoutVictory(color.other());
            }
        }
        board.victory_state()
    }
}

impl CurrentMatchStateClient {
    /// For a current match state which is already prepared for export, this
    /// function loads the player metadata from the database.
    pub async fn try_new(
        data: CurrentMatchState,
        room: &crate::ws::GameRoom,
        sender_metadata: SocketAuth,
        connection: &mut Connection,
    ) -> Result<Self, anyhow::Error> {
        let (white_player, black_player) = load_user_data_for_game(&data.key, connection).await?;

        let sender_identity = SocketIdentity::resolve_user(&sender_metadata, connection).await?;

        let mut white_control = room.white_player.test(&sender_identity);
        let mut black_control = room.black_player.test(&sender_identity);

        // If the sender is controlling one side and the other side is a frontend AI,
        // then they are allowed to control the frontend AI. We need to send the
        // control accordingly as `LockedByYourFrontendAi`.
        if white_control.can_control_or_take_over() && user::is_frontend_ai(&black_player) {
            black_control = ControlLevel::LockedByYourFrontendAi;
        }
        if black_control.can_control_or_take_over() && user::is_frontend_ai(&white_player) {
            white_control = ControlLevel::LockedByYourFrontendAi;
        }

        Ok(Self {
            key: data.key,
            actions: data.actions,
            is_rollback: data.is_rollback,
            controlling_player: data.controlling_player,
            timer: data.timer,
            victory_state: data.victory_state,
            setup_options: data.setup_options,
            white_player,
            black_player,
            white_control,
            black_control,
        })
    }

    pub async fn try_new_without_sender(
        data: CurrentMatchState,
        connection: &mut Connection,
    ) -> Result<Self, anyhow::Error> {
        let (white_player, black_player) = load_user_data_for_game(&data.key, connection).await?;

        Ok(Self {
            key: data.key,
            actions: data.actions,
            is_rollback: data.is_rollback,
            controlling_player: data.controlling_player,
            timer: data.timer,
            victory_state: data.victory_state,
            setup_options: data.setup_options,
            white_player,
            black_player,
            white_control: ControlLevel::LockedByOther,
            black_control: ControlLevel::LockedByOther,
        })
    }
}

impl CompressedMatchStateClient {
    /// Tries to create a new COMPRESSED match state out of a synchronized match and an
    /// already projected board.
    pub async fn try_new(
        sync_match: &SynchronizedMatch,
        board: &pacosako::DenseBoard,
        connection: &mut Connection,
    ) -> Result<Self, ServerError> {
        let victory_state = CurrentMatchState::victory_state(board, &sync_match.timer);
        let (white_player, black_player) =
            load_user_data_for_game(&sync_match.key, connection).await?;

        Ok(Self {
            key: sync_match.key.clone(),
            current_fen: fen::write_fen(board),
            victory_state,
            timer: sync_match.timer.clone(),
            white_player,
            black_player,
        })
    }
}

/// This implementation contains most of the "Business Logic" of the match.
impl SynchronizedMatch {
    pub fn new_with_key(key: &str, params: MatchParameters) -> Self {
        let setup_options = SetupOptions {
            safe_mode: params.safe_mode.unwrap_or(true),
            draw_after_n_repetitions: params.draw_after_n_repetitions.unwrap_or(3),
            starting_fen: variants::piece_setup_fen(params.piece_setup.unwrap_or(PieceSetupParameters::DefaultPieceSetup)),
        };

        Self {
            key: key.to_owned(),
            actions: Vec::default(),
            timer: params.timer.map(|t| t.into()),
            setup_options,
            white_player: None,
            black_player: None,
        }
    }

    /// Reconstruct the board state
    pub fn project(&self) -> Result<pacosako::DenseBoard, PacoError> {
        // Here we don't need to validate the move, this was done before they
        // have been added to the action list.
        let mut board = pacosako::DenseBoard::with_options(&self.setup_options)?;
        for action in &self.actions {
            board.execute_trusted(action.action)?;
        }
        Ok(board)
    }

    /// Validate and execute an action.
    pub fn do_action(&mut self, new_action: PacoAction) -> Result<CurrentMatchState, PacoError> {
        let mut board = self.project()?;
        let controlling_player = board.controlling_player();
        self.ensure_timer_is_running();
        self.update_timer(controlling_player);

        // Check if the timer has run out, in that case we return an error.
        // Timing out the timer like this is not a problem, because the timeout
        // will ping this game instance (or may already have) and this will
        // broadcast the game state to all connections.
        if let Some(timer) = &self.timer {
            if let TimerState::Timeout(_) = timer.get_state() {
                return Err(PacoError::NotYourTurn);
            }
        }

        board.execute(new_action)?;
        self.actions.push(StampedAction {
            action: new_action,
            timestamp: Utc::now(),
        });

        // Check if control changed. That would indicate that we need to add a
        // timer increment for the player that just finished their turn.
        if board.controlling_player() != controlling_player {
            if let Some(ref mut timer) = &mut self.timer {
                timer.increment(controlling_player);
            }
        }

        if board.victory_state().is_over() {
            if let Some(timer) = &mut self.timer {
                timer.stop();
            }
        }

        CurrentMatchState::try_new(self, &board)
    }

    /// Gets the current state and the currently available legal actions.
    pub fn current_state(&self) -> Result<CurrentMatchState, PacoError> {
        CurrentMatchState::try_new(self, &self.project()?)
    }

    /// Rolls back the game state to the start of the turn of the current player.
    pub fn rollback(&mut self) -> Result<CurrentMatchState, PacoError> {
        Self::rollback_trusted_action_stack(&self.setup_options, &mut self.actions)?;
        let mut state = self.current_state()?;
        state.is_rollback = true;
        Ok(state)
    }

    /// Takes a board state that is provided in terms of an action history and
    /// rolls back an in-progress move. This will never change the active player.
    /// Rolling back on a settled board state does nothing.
    /// The action stack is assumed to only contain legal moves and the moves are
    /// not validated.
    fn rollback_trusted_action_stack(setup: &SetupOptions, actions: &mut Vec<StampedAction>) -> Result<(), PacoError> {
        let last_checkpoint_index =
            pacosako::find_last_checkpoint_index(setup, actions.iter().map(|a| &a.action))?;

        // Remove all moves to get back to last_checkpoint_index
        while actions.len() > last_checkpoint_index {
            actions.pop();
        }

        Ok(())
    }

    /// Checks if the timer is in NotStarted mode and starts it in that case.
    fn ensure_timer_is_running(&mut self) {
        if let Some(ref mut timer) = &mut self.timer {
            if timer.get_state() == TimerState::NotStarted {
                timer.start(Utc::now());
            }
        }
    }

    /// Updates the timer
    fn update_timer(&mut self, player: PlayerColor) {
        if let Some(ref mut timer) = self.timer {
            if timer.get_state() == TimerState::NotStarted {
                // Nothing to do #55
            } else if timer.get_state() == TimerState::Running {
                timer.use_time(player, Utc::now());
            }
        }
    }

    /// Is triggered when there may have been significant timer progress.
    pub fn timer_progress(&mut self) -> Result<CurrentMatchState, PacoError> {
        let board = self.project()?;

        self.update_timer(board.controlling_player());

        CurrentMatchState::try_new(self, &board)
    }

    /// Gives the player of the given color.
    pub fn player(&self, color: PlayerColor) -> Option<UserId> {
        match color {
            PlayerColor::White => self.white_player,
            PlayerColor::Black => self.black_player,
        }
    }
}

#[cfg(test)]
mod test {
    use pacosako::const_tile::*;

    use super::*;

    /// Does a move and mostly just checks that it does not crash.
    #[test]
    fn test_legal_moves_are_ok() {
        let mut game = SynchronizedMatch::new_with_key(
            "Game1",
            MatchParameters {
                timer: None,
                safe_mode: Some(false),
                draw_after_n_repetitions: None,
                ai_side_request: None,
                piece_setup: None,
            },
        );

        game.do_action(PacoAction::Lift(C2)).unwrap();
        let current_state = game.do_action(PacoAction::Place(C3)).unwrap();

        // recalculating the current state does not lead to surprises.
        let current_state_2 = game.current_state().unwrap();
        assert_eq!(current_state.key, current_state_2.key);
        let no_stamps: Vec<PacoAction> = current_state.actions.iter().map(|a| a.action).collect();
        let no_stamps_2: Vec<PacoAction> =
            current_state_2.actions.iter().map(|a| a.action).collect();
        assert_eq!(no_stamps, no_stamps_2);

        // there are two moves in the state.
        assert_eq!(current_state.actions.len(), 2);
    }
}
