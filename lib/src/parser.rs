use crate::types::{BoardPosition, PieceType};

use nom;
use nom::{bytes::complete::tag, combinator::map_res, IResult};
use std::collections::HashMap;
// Brief detour, writing a parser.

// A Matrix parser takes input of the following form:

// 8 .. .. .B BR .K .. .. ..
// 7 .P .. .. .P .. .. .P ..
// 6 .. PP .. .. .N QR .. ..
// 5 BB .. .. NP .. .P .. .P
// 4 P. PN .. .. .. PP .. P.
// 3 .. .. .. .. .Q .. .. ..
// 2 .. .. N. P. .. P. P. ..
// 1 .. R. .. .. .. R. K. ..
// * A  B  C  D  E  F  G  H

#[derive(Debug)]
pub struct Matrix(pub HashMap<BoardPosition, Square>);

#[derive(Debug, Clone)]
pub struct Square {
    pub white: Option<PieceType>,
    pub black: Option<PieceType>,
}

impl Square {
    pub fn pair(white: PieceType, black: PieceType) -> Self {
        Square {
            white: Some(white),
            black: Some(black),
        }
    }
    pub fn white(white: PieceType) -> Self {
        Square {
            white: Some(white),
            black: None,
        }
    }
    pub fn black(black: PieceType) -> Self {
        Square {
            white: None,
            black: Some(black),
        }
    }
}

fn matrix_transform(input: Vec<(u8, Vec<Square>)>) -> Matrix {
    let mut matrix = HashMap::new();

    for (row, entries) in input {
        for (x, square) in entries.iter().enumerate() {
            if square.white != None || square.black != None {
                if let Some(pos) = BoardPosition::new_checked(x as i8, row as i8 - 1) {
                    matrix.insert(pos, square.clone());
                }
            }
        }
    }

    Matrix(matrix)
}

pub fn matrix(input: &str) -> IResult<&str, Matrix> {
    let (input, raw) = nom::multi::separated_list(tag("\n"), row)(input)?;
    Ok((input, matrix_transform(raw)))
}

fn exchange_notation(input: &str) -> IResult<&str, Matrix> {
    let (input, raw) = nom::multi::separated_list(tag("\n"), unlabled_row)(input)?;
    let row_indices: Vec<u8> = vec![8, 7, 6, 5, 4, 3, 2, 1];
    let labled_rows: Vec<(u8, Vec<Square>)> =
        row_indices.into_iter().zip(raw.into_iter()).collect();

    Ok((input, matrix_transform(labled_rows)))
}

pub fn try_exchange_notation(input: &str) -> Option<Matrix> {
    exchange_notation(input).map(|x| x.1).ok()
}

fn row(input: &str) -> IResult<&str, (u8, Vec<Square>)> {
    let (input, index) = nom::character::streaming::one_of("12345678")(input)?;
    let (input, _) = tag(" ")(input)?;
    let (input, content) = nom::multi::separated_list(tag(" "), square)(input)?;
    Ok((input, (index.to_digit(10).unwrap_or(0) as u8, content)))
}

fn unlabled_row(input: &str) -> IResult<&str, Vec<Square>> {
    let (input, content) = nom::multi::separated_list(tag(" "), square)(input)?;
    Ok((input, content))
}

fn square(input: &str) -> IResult<&str, Square> {
    let (input, white) = piece(input)?;
    let (input, black) = piece(input)?;
    Ok((input, Square { white, black }))
}

// Parses a single character into a piece type.
fn piece(input: &str) -> IResult<&str, Option<PieceType>> {
    map_res(nom::character::streaming::one_of(".PRNBQK"), from_piece)(input)
}

// Converts a character into a piece type
fn from_piece(input: char) -> Result<Option<PieceType>, &'static str> {
    use PieceType::*;
    match input {
        '.' => Ok(None),
        'P' => Ok(Some(Pawn)),
        'R' => Ok(Some(Rock)),
        'N' => Ok(Some(Knight)),
        'B' => Ok(Some(Bishop)),
        'Q' => Ok(Some(Queen)),
        'K' => Ok(Some(King)),
        _ => Err("invalid token"),
    }
}
