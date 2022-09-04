use pacosako::{PacoAction, PacoBoard, PacoError};

pub(crate) fn legal_moves(fen: &str, actions: &[PacoAction]) -> Result<Vec<PacoAction>, PacoError> {
    let mut board = pacosako::fen::parse_fen(fen)?;
    for action in actions {
        board.execute(*action)?;
    }
    board.actions()
}
