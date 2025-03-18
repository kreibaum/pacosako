//! Test class where we define some performance tests. We can't use criterion,
//! because it does not support binaries. We need to test with the binary,
//! because we want database access to get good data to test with. This is
//! defined in the backend binary, not the library.

mod all_settled_states;

use std::io::Write;

use pacosako::{DenseBoard, PacoAction};

use crate::{config, db::Connection, sync_match::SynchronizedMatch};
// Loads games MIN_GAME_ID..=MAX_GAME_ID, inclusive
// Bad apples are identified until 3000.
const MIN_GAME_ID: i64 = 1;
// const MAX_GAME_ID: i64 = 100;
const MAX_GAME_ID: i64 = 5000;
const MIN_GAME_ACTION_COUNT: usize = 12; // Only keep games with at least this many actions

// Use regex [0-9]{5} in the csv to find games that are really slow (> 10s).
#[rustfmt::skip]
const BAD_APPLES: [i64; 45] = [183, 288, 301, 374, 376, 377, 378, 431, 484, 914,
    1194, 1247, 1249, 1389, 1432, 1555, 1619, 1621, 1806, 1854, 1886, 1887, 1977,
    1978, 2038, 2414, 2448, 2543, 2649, 2726, 2727, 2804, 2892, 2917, 2991, 2992,
    2998, 3000, 3403, 3568, 3878, 4102, 4818, 4919, 4931];

// Note that 1977, 1978, 2892, 4919, 4931 are really bad.

#[tokio::test]
// #[ignore] // Can't run in CI, because it needs "production" database access
async fn paco_2_performance() {
    let config = config::load_config();

    // init_logger();

    // Setup database
    let pool = crate::init_database_pool(config.clone()).await;
    let mut conn = pool.0.acquire().await.unwrap();

    // Load games from database
    let timer = PerfTimer::new();
    let mut games = Vec::with_capacity((MAX_GAME_ID - MIN_GAME_ID) as usize);
    for i in MIN_GAME_ID..=MAX_GAME_ID {
        if !BAD_APPLES.contains(&i) {
            games.push(load_board(i, &mut conn).await);
        }
    }
    println!("Loaded {} games in {:?}", games.len(), timer.stop());

    // Iterate with i backwards, removing any board with .actions.len() < MIN_GAME_ACTION_COUNT
    for i in (0..games.len()).rev() {
        if games[i].actions.len() < MIN_GAME_ACTION_COUNT {
            games.remove(i);
        }
    }

    println!(
        "{} games have at least {} actions",
        games.len(),
        MIN_GAME_ACTION_COUNT
    );

    // Now do a replay analysis on all these games
    // Open a file to write individual performance metrics to
    let mut perf_csv = std::fs::File::create("paco_2_performance.csv").unwrap();

    let timer = PerfTimer::new();
    let mut analysis = Vec::with_capacity(games.len());
    for game in games {
        let i_timer = PerfTimer::new();
        let actions: Vec<PacoAction> = game.actions.iter().map(|a| a.into()).collect();
        analysis.push(pacosako::analysis::history_to_replay_notation(
            DenseBoard::new(),
            &actions,
        ));
        // Write to our performance file
        let elapsed = i_timer.stop().as_micros();
        let key = game.key;
        let line = format!("{}, {}\n", key, elapsed);
        perf_csv.write_all(line.as_bytes()).unwrap();
    }
    println!("Analyzed {} games in {:?}", analysis.len(), timer.stop());
    // Close the file
    perf_csv.flush().unwrap();

    // assert_eq!(1, 2);
}

async fn load_board(id: i64, conn: &mut Connection) -> SynchronizedMatch {
    crate::db::game::select(id, conn)
        .await
        .unwrap_or_else(|e| panic!("Error loading game {} from database, {:?}", id, e))
        .expect("Game does not exist on database")
    // .project()
}

struct PerfTimer(std::time::Instant);

impl PerfTimer {
    fn new() -> Self {
        Self(std::time::Instant::now())
    }

    fn stop(self) -> std::time::Duration {
        std::time::Instant::now() - self.0
    }
}
