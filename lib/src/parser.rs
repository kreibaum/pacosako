use crate::types::{BoardPosition, PieceType};
use crate::PlayerColor::*;
use crate::{Hand, PacoError, PlayerColor};

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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
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

    pub fn flip(&self) -> Square {
        Square {
            black: self.white,
            white: self.black,
        }
    }

    pub fn flip_if(&self, condition: bool) -> Square {
        if condition {
            self.flip()
        } else {
            *self
        }
    }

    pub fn is_empty(&self) -> bool {
        self.white.is_none() && self.black.is_none()
    }

    pub fn is_pair(&self) -> bool {
        self.white.is_some() && self.black.is_some()
    }

    pub fn from_hand(hand: &Hand, controlling_player: PlayerColor) -> Self {
        Square {
            white: hand.piece(),
            black: hand.partner(),
        }
            .flip_if(controlling_player == Black)
    }

    /// Turns a square into a hand. We need some extra information to do that.
    /// Returns a result, because not all squares can be turned into hands.
    pub fn as_hand(
        &self,
        controlling_player: PlayerColor,
        position: BoardPosition,
    ) -> Result<Hand, PacoError> {
        let assuming_white = self.flip_if(controlling_player == Black);
        if let Some(piece) = assuming_white.white {
            if let Some(partner) = assuming_white.black {
                Ok(Hand::Pair {
                    position,
                    piece,
                    partner,
                })
            } else {
                Ok(Hand::Single { position, piece })
            }
        } else if assuming_white.black.is_none() {
            Ok(Hand::Empty)
        } else {
            Err(PacoError::InputFenMalformed(
                "Lifted piece is of the wrong color".to_string(),
            ))
        }
    }
}

fn matrix_transform(input: Vec<(u8, Vec<Square>)>) -> Matrix {
    let mut matrix: HashMap<BoardPosition, Square> = HashMap::new();

    for (row, entries) in input {
        for (x, square) in entries.iter().enumerate() {
            if square.white.is_some() || square.black.is_some() {
                if let Some(pos) = BoardPosition::new_checked(x as i8, row as i8 - 1) {
                    matrix.insert(pos, *square);
                }
            }
        }
    }

    Matrix(matrix)
}

pub fn matrix(input: &str) -> IResult<&str, Matrix> {
    let (input, raw) = nom::multi::separated_list0(tag("\n"), row)(input)?;
    Ok((input, matrix_transform(raw)))
}

fn exchange_notation(input: &str) -> IResult<&str, Matrix> {
    let (input, raw) = nom::multi::separated_list0(tag("\n"), unlabeled_row)(input)?;
    let row_indices: Vec<u8> = vec![8, 7, 6, 5, 4, 3, 2, 1];
    let labeled_rows: Vec<(u8, Vec<Square>)> = row_indices.into_iter().zip(raw).collect();

    Ok((input, matrix_transform(labeled_rows)))
}

pub fn try_exchange_notation(input: &str) -> Option<Matrix> {
    exchange_notation(input).map(|x| x.1).ok()
}

fn row(input: &str) -> IResult<&str, (u8, Vec<Square>)> {
    let (input, index) = nom::character::streaming::one_of("12345678")(input)?;
    let (input, _) = tag(" ")(input)?;
    let (input, content) = nom::multi::separated_list0(tag(" "), square)(input)?;
    Ok((input, (index.to_digit(10).unwrap_or(0) as u8, content)))
}

fn unlabeled_row(input: &str) -> IResult<&str, Vec<Square>> {
    let (input, content) = nom::multi::separated_list0(tag(" "), square)(input)?;
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
        'R' => Ok(Some(Rook)),
        'N' => Ok(Some(Knight)),
        'B' => Ok(Some(Bishop)),
        'Q' => Ok(Some(Queen)),
        'K' => Ok(Some(King)),
        _ => Err("invalid token"),
    }
}
