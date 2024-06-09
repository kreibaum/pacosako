//! Provides various Paco Ŝako functions for use in Python.
//! Note that while the Julia module focuses on supporting AI training and evaluation,
//! this Python module is designed to support for various statistical analysis tasks.
//!
//! The Python module is implemented using the PyO3 library.
//! https://pyo3.rs/
//!
//! (Re-)compile using
//! ```shell
//! maturin develop
//! ```

use pyo3::exceptions::PyValueError;
use pyo3::prelude::*;
use serde::Deserialize;

use pacosako::{DenseBoard, PacoAction};
use pacosako::analysis::history_to_replay_notation;

/// Formats the sum of two numbers as string.
#[pyfunction]
fn sum_as_string(a: usize, b: usize) -> PyResult<String> {
    Ok((a + b).to_string())
}

#[derive(Deserialize)]
struct ReplayDataStub {
    actions: Vec<StampedAction>,
}

/// A paco sako action together with a timestamp that remembers when it was done.
/// This timestamp is important for replays.
#[derive(Deserialize, Clone, Debug)]
pub struct StampedAction {
    #[serde(flatten)]
    action: PacoAction,
    // We don't need the timestamp for analysis.
    // timestamp: DateTime<Utc>,
}


#[pyfunction]
pub fn analyze_replay(replay: &str) -> PyResult<String> {
    let replay_data: ReplayDataStub = serde_json::from_str(replay).unwrap();

    let initial_board = DenseBoard::new();
    let actions = replay_data.actions.iter().map(|a| a.action.clone()).collect::<Vec<PacoAction>>();

    let replay_data = history_to_replay_notation(initial_board, &actions).map_err(|e| {
        PyValueError::new_err(format!("Failed to analyze replay: {}", e))
    })?;

    // use serde to turns this into a json string:
    let replay_data_string = serde_json::to_string(&replay_data).unwrap();

    Ok(replay_data_string)
}

/// A Python module implemented in Rust.
#[pymodule]
fn pypacosako(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(sum_as_string, m)?)?;
    m.add_function(wrap_pyfunction!(analyze_replay, m)?)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_GAME_15313: &'static str = r#"{"key":"15313","actions":[{"Lift":12,"timestamp":"2023-11-28T14:06:45.121445759Z"},{"Place":28,"timestamp":"2023-11-28T14:06:46.804114774Z"},{"Lift":52,"timestamp":"2023-11-28T14:06:50.960078747Z"},{"Place":36,"timestamp":"2023-11-28T14:06:52.299956235Z"},{"Lift":11,"timestamp":"2023-11-28T14:07:09.102758646Z"},{"Place":27,"timestamp":"2023-11-28T14:07:10.241282502Z"},{"Lift":51,"timestamp":"2023-11-28T14:07:11.220234245Z"},{"Place":35,"timestamp":"2023-11-28T14:07:12.223287382Z"},{"Lift":1,"timestamp":"2023-11-28T14:07:13.920336124Z"},{"Place":18,"timestamp":"2023-11-28T14:07:15.103081141Z"},{"Lift":57,"timestamp":"2023-11-28T14:07:19.743563880Z"},{"Place":42,"timestamp":"2023-11-28T14:07:21.240380988Z"},{"Lift":2,"timestamp":"2023-11-28T14:07:24.680199010Z"},{"Place":38,"timestamp":"2023-11-28T14:07:31.240126676Z"},{"Lift":58,"timestamp":"2023-11-28T14:07:38.980120329Z"},{"Place":30,"timestamp":"2023-11-28T14:07:41.860239040Z"},{"Lift":38,"timestamp":"2023-11-28T14:07:45.798898616Z"},{"Place":52,"timestamp":"2023-11-28T14:07:48.063166605Z"},{"Lift":62,"timestamp":"2023-11-28T14:07:52.758984310Z"},{"Place":45,"timestamp":"2023-11-28T14:07:54.248245263Z"},{"Lift":3,"timestamp":"2023-11-28T14:08:01.359283741Z"},{"Place":30,"timestamp":"2023-11-28T14:08:03.920191598Z"},{"Lift":30,"timestamp":"2023-11-28T14:08:05.822909488Z"},{"Place":58,"timestamp":"2023-11-28T14:08:08.880163101Z"},{"Lift":58,"timestamp":"2023-11-28T14:08:14.880135641Z"},{"Place":30,"timestamp":"2023-11-28T14:08:16.702798467Z"},{"Lift":30,"timestamp":"2023-11-28T14:08:18.783676763Z"},{"Place":58,"timestamp":"2023-11-28T14:08:22.600341929Z"},{"Lift":52,"timestamp":"2023-11-28T14:08:23.992276725Z"},{"Place":59,"timestamp":"2023-11-28T14:08:27.262906520Z"},{"Lift":45,"timestamp":"2023-11-28T14:08:45.879806395Z"},{"Place":62,"timestamp":"2023-11-28T14:08:47.744003382Z"},{"Lift":58,"timestamp":"2023-11-28T14:08:49.903039901Z"},{"Place":57,"timestamp":"2023-11-28T14:08:51.540857370Z"},{"Lift":60,"timestamp":"2023-11-28T14:08:54.660485313Z"},{"Place":51,"timestamp":"2023-11-28T14:08:56.400031973Z"},{"Lift":57,"timestamp":"2023-11-28T14:08:57.519687952Z"},{"Place":58,"timestamp":"2023-11-28T14:08:58.680005243Z"},{"Lift":53,"timestamp":"2023-11-28T14:09:16.159430148Z"},{"Place":37,"timestamp":"2023-11-28T14:09:17.423048340Z"},{"Lift":5,"timestamp":"2023-11-28T14:09:18.600415432Z"},{"Place":40,"timestamp":"2023-11-28T14:09:27.343869219Z"},{"Lift":42,"timestamp":"2023-11-28T14:09:33.319968393Z"},{"Place":59,"timestamp":"2023-11-28T14:09:35.423621353Z"},{"Place":52,"timestamp":"2023-11-28T14:09:39.048326079Z"},{"Lift":40,"timestamp":"2023-11-28T14:09:46.280750257Z"},{"Place":49,"timestamp":"2023-11-28T14:09:47.424147947Z"},{"Lift":52,"timestamp":"2023-11-28T14:10:00.888278958Z"},{"Place":60,"timestamp":"2023-11-28T14:10:02.680685039Z"},{"Lift":0,"timestamp":"2023-11-28T14:10:09.882094710Z"},{"Place":3,"timestamp":"2023-11-28T14:10:10.999903752Z"},{"Lift":60,"timestamp":"2023-11-28T14:10:16.143278227Z"},{"Place":59,"timestamp":"2023-11-28T14:10:17.221907975Z"},{"Place":44,"timestamp":"2023-11-28T14:10:27.139995266Z"},{"Lift":13,"timestamp":"2023-11-28T14:10:31.220342252Z"},{"Place":29,"timestamp":"2023-11-28T14:10:33.200107471Z"},{"Lift":36,"timestamp":"2023-11-28T14:10:37.400740902Z"},{"Place":29,"timestamp":"2023-11-28T14:10:38.063910380Z"},{"Lift":28,"timestamp":"2023-11-28T14:10:45.560864111Z"},{"Place":35,"timestamp":"2023-11-28T14:10:46.500139280Z"},{"Lift":44,"timestamp":"2023-11-28T14:10:47.423004366Z"},{"Place":59,"timestamp":"2023-11-28T14:10:48.783235529Z"},{"Place":60,"timestamp":"2023-11-28T14:10:54.623009767Z"},{"Lift":3,"timestamp":"2023-11-28T14:11:15.203862023Z"},{"Place":19,"timestamp":"2023-11-28T14:11:17.580100093Z"},{"Lift":60,"timestamp":"2023-11-28T14:11:29.100721678Z"},{"Place":59,"timestamp":"2023-11-28T14:11:30.260522799Z"},{"Place":44,"timestamp":"2023-11-28T14:11:39.241113359Z"},{"Lift":19,"timestamp":"2023-11-28T14:11:42.121116240Z"},{"Place":23,"timestamp":"2023-11-28T14:11:43.764757912Z"},{"Lift":29,"timestamp":"2023-11-28T14:11:50.450891942Z"},{"Place":21,"timestamp":"2023-11-28T14:11:51.950698457Z"},{"Lift":23,"timestamp":"2023-11-28T14:11:52.737640444Z"},{"Place":39,"timestamp":"2023-11-28T14:11:56.669624740Z"},{"Lift":21,"timestamp":"2023-11-28T14:12:04.449887750Z"},{"Place":13,"timestamp":"2023-11-28T14:12:05.249601874Z"},{"Lift":4,"timestamp":"2023-11-28T14:12:06.270122051Z"},{"Place":5,"timestamp":"2023-11-28T14:12:07.729668696Z"},{"Lift":62,"timestamp":"2023-11-28T14:12:10.795126294Z"},{"Place":45,"timestamp":"2023-11-28T14:12:11.969799857Z"},{"Lift":39,"timestamp":"2023-11-28T14:12:13.353660640Z"},{"Place":38,"timestamp":"2023-11-28T14:12:18.206948993Z"},{"Lift":44,"timestamp":"2023-11-28T14:12:25.887245618Z"},{"Place":34,"timestamp":"2023-11-28T14:12:29.044465401Z"},{"Lift":38,"timestamp":"2023-11-28T14:12:31.805630564Z"},{"Place":22,"timestamp":"2023-11-28T14:12:36.004871566Z"},{"Lift":45,"timestamp":"2023-11-28T14:12:42.684811131Z"},{"Place":60,"timestamp":"2023-11-28T14:12:44.044753314Z"},{"Lift":22,"timestamp":"2023-11-28T14:12:46.804588304Z"},{"Place":20,"timestamp":"2023-11-28T14:12:48.565303347Z"},{"Lift":37,"timestamp":"2023-11-28T14:12:59.664430354Z"},{"Place":29,"timestamp":"2023-11-28T14:13:00.990686431Z"},{"Lift":20,"timestamp":"2023-11-28T14:13:02.143758056Z"},{"Place":44,"timestamp":"2023-11-28T14:13:08.240696740Z"},{"Lift":51,"timestamp":"2023-11-28T14:13:10.170558823Z"},{"Place":52,"timestamp":"2023-11-28T14:13:11.231764856Z"},{"Lift":44,"timestamp":"2023-11-28T14:13:12.590429928Z"},{"Place":52,"timestamp":"2023-11-28T14:13:13.451458016Z"}],"is_rollback":false,"controlling_player":"Black","timer":{"last_timestamp":"2023-11-28T14:13:13.451457501Z","time_left_white":190.051,"time_left_black":136.548,"timer_state":"Stopped","config":{"time_budget_white":240.0,"time_budget_black":240.0,"increment":5.0}},"victory_state":{"PacoVictory":"White"},"setup_options":{"safe_mode":true,"draw_after_n_repetitions":3},"white_player":null,"black_player":null,"white_control":"LockedByOther","black_control":"LockedByOther"}"#;

    #[test]
    fn replay_analysis() {
        analyze_replay(TEST_GAME_15313).unwrap();
    }
}