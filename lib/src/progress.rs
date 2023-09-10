//! Progress reporting for long-running operations.

use serde::Serialize;

/// A progress report. We don't type the topic and just use a string instead.
#[derive(Serialize)]
pub struct Progress {
    pub topic: &'static str,
    pub total: usize,
    pub current: usize,
}

impl Progress {
    pub fn new(topic: &'static str, total: usize, current: usize) -> Self {
        Self {
            topic,
            total,
            current,
        }
    }

    pub fn is_finished(&self) -> bool {
        self.current == self.total
    }
}
