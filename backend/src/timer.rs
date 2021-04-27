use chrono::{DateTime, Duration, Utc};
use pacosako::PlayerColor;
use serde::{Deserialize, Serialize};
use std::convert::From;

/// The timer module should encapsulate the game timer state. It is importing
/// pacosako in order to work with the player colors. Otherwise it is not
/// specific to Paco Ŝako.

#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct TimerConfig {
    #[serde(
        serialize_with = "serialize_seconds",
        deserialize_with = "deserialize_seconds"
    )]
    pub time_budget_white: Duration,
    #[serde(
        serialize_with = "serialize_seconds",
        deserialize_with = "deserialize_seconds"
    )]
    pub time_budget_black: Duration,
    #[serde(default)]
    #[serde(
        serialize_with = "serialize_seconds_optional",
        deserialize_with = "deserialize_seconds_optional"
    )]
    pub increment: Option<Duration>,
}

#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct Timer {
    last_timestamp: DateTime<Utc>,
    #[serde(
        serialize_with = "serialize_seconds",
        deserialize_with = "deserialize_seconds"
    )]
    time_left_white: Duration,
    #[serde(
        serialize_with = "serialize_seconds",
        deserialize_with = "deserialize_seconds"
    )]
    time_left_black: Duration,
    timer_state: TimerState,
    config: TimerConfig,
}

/// There is no default implementation for serde::Serialize for Duration, so we
/// have to provide it ourself. This also gives us the flexibility to decide
/// how much precision we expose to the client.
fn serialize_seconds<S: serde::Serializer>(duration: &Duration, s: S) -> Result<S::Ok, S::Error> {
    s.serialize_f32(duration.num_milliseconds() as f32 / 1000f32)
}

/// Like serialize_seconds, but optional
fn serialize_seconds_optional<S: serde::Serializer>(
    duration: &Option<Duration>,
    s: S,
) -> Result<S::Ok, S::Error> {
    match duration {
        Some(duration) => s.serialize_f32(duration.num_milliseconds() as f32 / 1000f32),
        None => s.serialize_none(),
    }
}

/// There is no default implementation for serde::Serialize for Duration, so we
/// have to provide it ourself. This also gives us the flexibility to decide
/// how much precision we expose to the client.
fn deserialize_seconds<'de, D: serde::Deserializer<'de>>(d: D) -> Result<Duration, D::Error> {
    let seconds: f32 = serde::de::Deserialize::deserialize(d)?;
    Ok(Duration::milliseconds((1000.0 * seconds) as i64))
}

/// Like deserialize_seconds, but optional
fn deserialize_seconds_optional<'de, D: serde::Deserializer<'de>>(
    d: D,
) -> Result<Option<Duration>, D::Error> {
    let seconds: Result<f32, D::Error> = serde::de::Deserialize::deserialize(d);
    if let Ok(seconds) = seconds {
        Ok(Some(Duration::milliseconds((1000.0 * seconds) as i64)))
    } else {
        Ok(None)
    }
}

impl Timer {
    // Start a timer. This does nothing when the Timer is alread running or already timed out.
    pub fn start(&mut self, start_time: DateTime<Utc>) {
        if self.timer_state == TimerState::NotStarted {
            self.last_timestamp = start_time;
            self.timer_state = TimerState::Running;
        }
    }

    pub fn use_time(&mut self, player: PlayerColor, now: DateTime<Utc>) -> TimerState {
        if self.timer_state != TimerState::Running {
            return self.timer_state;
        }

        let time_passed: Duration = now - self.last_timestamp;

        let time_left = match player {
            PlayerColor::White => {
                self.time_left_white = self.time_left_white - time_passed;
                self.time_left_white
            }
            PlayerColor::Black => {
                self.time_left_black = self.time_left_black - time_passed;
                self.time_left_black
            }
        };

        self.last_timestamp = now;

        // Check if the time ran out
        if time_left <= Duration::nanoseconds(0) {
            self.timer_state = TimerState::Timeout(player);
        }

        self.timer_state
    }

    /// Stops the timer
    pub fn stop(&mut self) {
        self.timer_state = TimerState::Stopped
    }

    /// Increases the given players budget by the increment configured in the
    /// timer. This can not be directly included in the use time, because a
    /// player may use time multiple timer in a single turn. (Each action calls
    /// use time.)
    pub fn increment(&mut self, player: PlayerColor) {
        if let Some(increment) = self.config.increment {
            match player {
                PlayerColor::White => {
                    self.time_left_white = self.time_left_white + increment;
                }
                PlayerColor::Black => {
                    self.time_left_black = self.time_left_black + increment;
                }
            }
        }
    }

    pub fn get_state(&self) -> TimerState {
        self.timer_state
    }

    /// Returns the time at which the timer would run out if the given player
    /// retains controll until then.
    pub fn timeout(&self, player: PlayerColor) -> DateTime<Utc> {
        let time_left = match player {
            PlayerColor::White => self.time_left_white,
            PlayerColor::Black => self.time_left_black,
        };

        self.last_timestamp + time_left
    }
}

/// Gives the current state of the timer. When the timer is running it does
/// not know which player is currently controlling it. The time will be reduced
/// when an action is send to the server.
#[derive(Debug, PartialEq, Eq, Copy, Clone, Serialize, Deserialize)]
pub enum TimerState {
    /// A timer is in this state, when the game has not started yet.
    NotStarted,
    /// A timer is in this state, while the game is in progress.
    Running,
    /// A timer is in timeout when one party runs out of time. The color stored
    /// in here is the loosing player who used up their time.
    Timeout(PlayerColor),
    /// A timer is stopped when one party wins.
    Stopped,
}

impl TimerState {
    pub fn is_finished(self) -> bool {
        match self {
            TimerState::NotStarted => false,
            TimerState::Running => false,
            TimerState::Timeout(_) => true,
            TimerState::Stopped => true,
        }
    }
}

impl From<TimerConfig> for Timer {
    fn from(config: TimerConfig) -> Timer {
        Timer {
            last_timestamp: Utc::now(),
            time_left_white: config.time_budget_white.clone(),
            time_left_black: config.time_budget_black.clone(),
            timer_state: TimerState::NotStarted,
            config,
        }
    }
}

impl From<&TimerConfig> for Timer {
    fn from(config: &TimerConfig) -> Timer {
        Timer {
            last_timestamp: Utc::now(),
            time_left_white: config.time_budget_white.clone(),
            time_left_black: config.time_budget_black.clone(),
            timer_state: TimerState::NotStarted,
            config: config.clone(),
        }
    }
}

#[cfg(test)]
mod test {
    use super::*;

    fn test_timer_config() -> TimerConfig {
        TimerConfig {
            time_budget_white: Duration::seconds(5 * 60),
            time_budget_black: Duration::seconds(4 * 60),
            increment: None,
        }
    }

    #[test]
    fn create_timer_from_config() {
        let config: TimerConfig = test_timer_config();
        let timer: Timer = config.into();
        assert_eq!(timer.get_state(), TimerState::NotStarted);
        assert_eq!(timer.time_left_white, Duration::seconds(300));
        assert_eq!(timer.time_left_black, Duration::seconds(240));
    }

    #[test]
    fn test_start_timer() {
        let mut timer: Timer = test_timer_config().into();
        let now = Utc::now();

        timer.start(now);
        assert_eq!(timer.last_timestamp, now);
        assert_eq!(timer.get_state(), TimerState::Running);

        let now2 = now + Duration::seconds(3);
        timer.start(now2);
        assert_eq!(timer.last_timestamp, now);
        assert_eq!(timer.get_state(), TimerState::Running);

        timer.stop();
        assert_eq!(timer.get_state(), TimerState::Stopped);
    }

    #[test]
    fn test_use_time() {
        use PlayerColor::*;

        let mut timer: Timer = test_timer_config().into();
        let now = Utc::now();

        // Using time does not work when the timer is not running
        let unused_future = now + Duration::seconds(100);
        timer.use_time(White, unused_future);
        assert_eq!(timer.time_left_white, Duration::seconds(300));
        assert_eq!(timer.time_left_black, Duration::seconds(240));

        timer.start(now);

        // Use 15 seconds from the white player
        let now = now + Duration::seconds(15);
        timer.use_time(White, now);
        assert_eq!(timer.time_left_white, Duration::seconds(285));
        assert_eq!(timer.time_left_black, Duration::seconds(240));
        assert_eq!(timer.get_state(), TimerState::Running);

        // Use 7 seconds from the black player
        let now = now + Duration::seconds(7);
        timer.use_time(Black, now);
        assert_eq!(timer.time_left_white, Duration::seconds(285));
        assert_eq!(timer.time_left_black, Duration::seconds(233));
        assert_eq!(timer.get_state(), TimerState::Running);

        // Use 8 seconds from the white player
        let now = now + Duration::seconds(8);
        timer.use_time(White, now);
        assert_eq!(timer.time_left_white, Duration::seconds(277));
        assert_eq!(timer.time_left_black, Duration::seconds(233));
        assert_eq!(timer.get_state(), TimerState::Running);

        // Use 500 seconds from the black player, this should yield a timeout.
        let now = now + Duration::seconds(500);
        timer.use_time(Black, now);
        assert_eq!(timer.time_left_white, Duration::seconds(277));
        assert_eq!(timer.time_left_black, Duration::seconds(-267));
        assert_eq!(timer.get_state(), TimerState::Timeout(Black));
    }

    #[test]
    fn test_use_increment() {
        use PlayerColor::*;
        let config = TimerConfig {
            time_budget_white: Duration::seconds(5 * 60),
            time_budget_black: Duration::seconds(5 * 60),
            increment: Some(Duration::seconds(5)),
        };

        let mut timer: Timer = config.into();

        let now = Utc::now();
        timer.start(now);

        // Use 15 seconds from the white player, and check that there is a 5
        // 5 second increment we get back.
        let now = now + Duration::seconds(15);
        timer.use_time(White, now);
        timer.increment(White);
        assert_eq!(timer.time_left_white, Duration::seconds(290));
        assert_eq!(timer.time_left_black, Duration::seconds(300));
        assert_eq!(timer.get_state(), TimerState::Running);
    }
}
