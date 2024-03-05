//! Utility test that loads all games from the database and then dumps all the
//! states into a CSV file. This allows me to understand which states
//! are the most common.
//!
//! I hope that this helps us identify openings and possibly build an opening
//! book.

use std::io::Write;

use pacosako::{DenseBoard, PacoBoard};

use crate::{config, db::Connection, sync_match::SynchronizedMatch};

#[tokio::test]
#[ignore] // Can't run in CI, because it needs "production" database access
async fn all_the_games() {
    let config = config::load_config();

    let pool = crate::init_database_pool(config.clone()).await;
    let mut conn = pool.0.acquire().await.unwrap();

    // select max(id) from game
    let max_game_id: i32 = sqlx::query!("select coalesce(max(id), 0) as mx from game")
        .fetch_one(&mut conn)
        .await
        .unwrap()
        .mx;

    let mut boards_csv = std::fs::File::create("all_boards.csv").unwrap();
    boards_csv
        .write_all("game_id,half_move_count,victory_state,fen\n".as_bytes())
        .unwrap();

    'outer: for i in 1..=max_game_id {
        let Some(replay) = load_board(i.into(), &mut conn).await else {
            continue 'outer;
        };

        let mut b1 = DenseBoard::new();
        for action in &replay.actions {
            if b1.execute(action.into()).is_err() {
                println!("Error in game {}, skipping", i);
                continue 'outer;
            }
        }

        let mut board = DenseBoard::new();

        for action in replay.actions {
            if board.execute((&action).into()).is_err() {
                println!("Error in game {}, skipping", i);
                continue 'outer;
            }
            if board.is_settled() {
                let fen = pacosako::fen::write_fen(&board);
                let line = format!(
                    "{},{},{:?},{}\n",
                    i,
                    board.half_move_count - 1,
                    b1.victory_state,
                    fen
                );
                boards_csv.write_all(line.as_bytes()).unwrap();
            }
        }
    }
    boards_csv.flush().unwrap();
}

async fn load_board(id: i64, conn: &mut Connection) -> Option<SynchronizedMatch> {
    crate::db::game::select(id, conn)
        .await
        .unwrap_or_else(|e| panic!("Error loading game {} from database, {:?}", id, e))
}
