use pacosako::{DenseBoard, EditorBoard, PacoError};

fn main() -> Result<(), PacoError> {
    let schema = "8 .. .. .. .. .K .B .. .R
7 .P .. .. .. .P .. .. .P
6 .. .. .P .. QB .R .P ..
5 .. .P .. .. BP .. N. ..
4 .. P. .. PQ .. .. BN PN
3 .. .. N. .. PP .. .. ..
2 P. .. P. .. .. P. .. P.
1 R. .. .. .. .. R. K. ..
* A  B  C  D  E  F  G  H";

    let parsed = pacosako::parser::matrix(schema);

    if let Ok((_, matrix)) = parsed {
        let board = DenseBoard::from_squares(matrix.0);

        // Print the board as json using serde.
        let pieces: EditorBoard = (&board).into();

        let sequences = pacosako::find_sako_sequences(&pieces);

        println!("{:?}", sequences);

        // Serialize it to a JSON string.
        let j = serde_json::to_string(&pieces).unwrap();
        println!("{}", j);

        // board.current_player = board.current_player().other();
        // analyse_sako(board)?;

        // Analyse board after a round trip throught Serde Json
        let editor_board: EditorBoard = serde_json::from_str(&j).unwrap();
        let search_result = pacosako::find_sako_sequences(&editor_board)?;
        println!("search_result: {:?}", search_result);
    }

    Ok(())
}
