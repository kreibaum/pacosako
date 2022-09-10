module NotationTest exposing (..)

{-| Tests to support the Notation module.
-}

import Expect
import Notation
import Sako exposing (Action(..), Color(..), Tile(..), Type(..))
import Test exposing (..)
import Time exposing (Posix, millisToPosix)


suite : Test
suite =
    describe "Test suite for Paco Ŝako notation"
        [ test "Empty list in, empty list out" <|
            \() ->
                Notation.compile
                    { actions = []
                    , timer = Nothing
                    , victoryState = Sako.Running
                    }
                    |> Expect.equal []
        , test "Simple move rendered" <|
            \() ->
                Notation.writeOut
                    [ Notation.StartMoveSingle Knight (Tile 1 0)
                    , Notation.EndMoveCalm (Tile 2 2)
                    ]
                    |> Expect.equal "Nb1>c3"
        , test "Union move rendered" <|
            \() ->
                Notation.writeOut
                    [ Notation.StartMoveUnion Bishop Rook (Tile 0 2)
                    , Notation.EndMoveCalm (Tile 3 5)
                    ]
                    |> Expect.equal "BRa3>d6"
        , test "Forming a union" <|
            \() ->
                Notation.writeOut
                    [ Notation.StartMoveSingle Queen (Tile 3 0)
                    , Notation.EndMoveFormUnion Pawn (Tile 7 4)
                    ]
                    |> Expect.equal "Qd1xh5"
        , test "Chaining moves" <|
            \() ->
                Notation.writeOut
                    [ Notation.StartMoveSingle Pawn (Tile 5 1)
                    , Notation.ContinueChain Pawn (Tile 4 2)
                    , Notation.ContinueChain Knight (Tile 5 3)
                    , Notation.EndMoveCalm (Tile 6 5)
                    ]
                    |> Expect.equal "f2>Pe3>Nf4>g6"
        , test "Compiled Notation for a single pawn moving forward" <|
            \() ->
                Notation.compile
                    { actions =
                        [ liftFrom 11
                        , placeAt 27
                        ]
                    , timer = Nothing
                    , victoryState = Sako.Running
                    }
                    |> Expect.equal
                        [ { moveNumber = 1
                          , color = White
                          , actions =
                                [ { actionIndex = 2
                                  , actions =
                                        [ Notation.StartMoveSingle Pawn (Tile 3 1)
                                        , Notation.EndMoveCalm (Tile 3 3)
                                        ]
                                  }
                                ]
                          }
                        ]
        , test "Compiled Notation that includes a chain and a union move" <|
            \() ->
                Notation.compile
                    { actions =
                        [ liftFrom 11
                        , placeAt 27
                        , liftFrom 52
                        , placeAt 36
                        , liftFrom 6
                        , placeAt 21
                        , liftFrom 36
                        , placeAt 27
                        , liftFrom 3
                        , placeAt 27
                        , placeAt 35
                        , liftFrom 27
                        , placeAt 19
                        , liftFrom 19
                        , placeAt 37
                        ]
                    , timer = Nothing
                    , victoryState = Sako.Running
                    }
                    |> Expect.equal
                        [ { moveNumber = 1
                          , color = White
                          , actions =
                                [ { actionIndex = 2
                                  , actions =
                                        [ Notation.StartMoveSingle Pawn (Tile 3 1)
                                        , Notation.EndMoveCalm (Tile 3 3)
                                        ]
                                  }
                                ]
                          }
                        , { moveNumber = 1
                          , color = Black
                          , actions =
                                [ { actionIndex = 4
                                  , actions =
                                        [ Notation.StartMoveSingle Pawn (Tile 4 6)
                                        , Notation.EndMoveCalm (Tile 4 4)
                                        ]
                                  }
                                ]
                          }
                        , { moveNumber = 2
                          , color = White
                          , actions =
                                [ { actionIndex = 6
                                  , actions =
                                        [ Notation.StartMoveSingle Knight (Tile 6 0)
                                        , Notation.EndMoveCalm (Tile 5 2)
                                        ]
                                  }
                                ]
                          }
                        , { moveNumber = 2
                          , color = Black
                          , actions =
                                [ { actionIndex = 8
                                  , actions =
                                        [ Notation.StartMoveSingle Pawn (Tile 4 4)
                                        , Notation.EndMoveFormUnion Pawn (Tile 3 3)
                                        ]
                                  }
                                ]
                          }
                        , { moveNumber = 3
                          , color = White
                          , actions =
                                [ { actionIndex = 10
                                  , actions =
                                        [ Notation.StartMoveSingle Queen (Tile 3 0)
                                        , Notation.ContinueChain Pawn (Tile 3 3)
                                        ]
                                  }
                                , { actionIndex = 11
                                  , actions =
                                        [ Notation.EndMoveCalm (Tile 3 4) ]
                                  }
                                ]
                          }
                        , { moveNumber = 3
                          , color = Black
                          , actions =
                                [ { actionIndex = 13
                                  , actions =
                                        [ Notation.StartMoveUnion Pawn Queen (Tile 3 3)
                                        , Notation.EndMoveCalm (Tile 3 2)
                                        ]
                                  }
                                ]
                          }
                        , { moveNumber = 4
                          , color = White
                          , actions =
                                [ { actionIndex = 15
                                  , actions =
                                        [ Notation.StartMoveUnion Queen Pawn (Tile 3 2)
                                        , Notation.EndMoveCalm (Tile 5 4)
                                        ]
                                  }
                                ]
                          }
                        ]
        ]


liftFrom : Int -> ( Action, Posix )
liftFrom flatCoordinate =
    ( Lift (Sako.tileFromFlatCoordinate flatCoordinate)
    , millisToPosix 0
    )


placeAt : Int -> ( Action, Posix )
placeAt flatCoordinate =
    ( Place (Sako.tileFromFlatCoordinate flatCoordinate)
    , millisToPosix 0
    )
