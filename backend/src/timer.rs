use pacosako::PlayerColor;
use std::convert::From;
use std::time::{Duration, Instant};

/// The timer module should encapsulate the game timer state. It is importing
/// pacosako in order to work with the player colors. Otherwise it is not
/// specific to Paco Ŝako.

#[derive(Clone)]
pub struct TimerConfig {
    time_budget_white: Duration,
    time_budget_black: Duration,
}

pub struct Timer {
    last_timestamp: Instant,
    time_left_white: Duration,
    time_left_black: Duration,
    timer_state: TimerState,
    config: TimerConfig,
}

impl Timer {
    // Start a timer. This does nothing when the Timer is alread running or already timed out.
    pub fn start(&mut self, start_time:Instant) {
        if self.timer_state == TimerState::Paused {
            self.last_timestamp = start_time;
            self.timer_state = TimerState::Running;
        }
    }
}

/// Gives the current state of the timer. When the timer is running it does
/// not know which player is currently controlling it. The time will be reduced
/// when an action is send to the server.
#[derive(Debug, PartialEq, Eq)]
pub enum TimerState {
    Paused,
    Running,
    Timeout(PlayerColor),
}

impl From<TimerConfig> for Timer {
    fn from(config: TimerConfig) -> Self {
        Timer {
            last_timestamp: Instant::now(),
            time_left_white : config.time_budget_white.clone(),
            time_left_black: config.time_budget_black.clone(),
            timer_state: TimerState::Paused,
            config,
        }
    }
}


#[cfg(test)]
mod test {
    use super::*;

    static TEST_TIMER_CONFIG : TimerConfig = TimerConfig {
            time_budget_white: Duration::from_secs(5 * 60),
            time_budget_black: Duration::from_secs(4 * 60),
        };
    
    #[test]
    fn create_timer_from_config() {
        let config : TimerConfig = TEST_TIMER_CONFIG.clone();
        let timer : Timer = config.into();
        assert_eq!(timer.timer_state, TimerState::Paused);
        assert_eq!(timer.time_left_white, Duration::from_secs(300));
        assert_eq!(timer.time_left_black, Duration::from_secs(240));
    }

    #[test]
    fn test_start_timer() {
        let mut timer : Timer = TEST_TIMER_CONFIG.clone().into();
        let now = Instant::now();

        timer.start(now);
        assert_eq!(timer.last_timestamp, now);
        assert_eq!(timer.timer_state, TimerState::Running);

        let now2 = now + Duration::from_secs(3);
        timer.start(now2);
        assert_eq!(timer.last_timestamp, now);
        assert_eq!(timer.timer_state, TimerState::Running);
    }
}