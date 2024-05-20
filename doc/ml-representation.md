# Machine Learning Representation for Paco Ŝako

This document describes the machine learning (ML) representation
we are using for Paco Ŝako. 

An example of the index representation is shown at the bottom.

## Options

The following options are available:

- `USE_PERSPECTIVE` - Is the current player at the bottom, or white?
- `WITH_MUST_LIFT` - Adds a layer that hints about the expected action type.
- `WITH_MUST_PROMOTE` - Adds a layer that hints about the expected action type.

The effects are described in detail on the layers they affect.

## Tensor Representation

The game state is represented as a `8x8x?` tensor where the exact amount of layers
depends on the representation options. There are at least 30 layers for the
oldest models we have, but some newer models require a richer representation.

### Piece Position Layers

The first 24 layers are represented for piece positions. Here each piece type
has its own layer, and then each color also has their own layer. That brings us
to 6x2=12 layers for pieces on the board. The next 12 layers are only used to
represent the lifted piece(s).

This is a very sparse tensor, it is mostly 0 with only 32 positions set to 1.

Using 0 indexing, the layers are:

```
Settled: 0-11
  Bottom Player: 0-5
    Pawn: Layer 0
    ...
    King: Layer 5
  Top Player: 6-11
Lifted: 12-23
  Bottom Player: 12-17
  Top: 18-23
```

The Bottom/Top wording is intentionally ambiguous. There are two modes of the
representation:

The `USE_PERSPECTIVE = 1` representation:
- The currently acting player is always the bottom player. Those are "my" pieces.
- The opponent is always the top player. Those are "their" pieces.
- You can think of this as representing the board from the perspective of the
  current player.
- The board is **flipped** along the Y axis, not rotated. Your king is still on E.

The `USE_PERSPECTIVE = 0` representation:
- The white pieces are used for the bottom player. The black ones for the top player.
- There is an additional layer (shown later) to indicate who is playing.

### En Passant Layer

This layer is always used. It always has index 24. This layer is usually all zeros,
but in en passant situations the en passant square is set to 1.

This layer is affected by `USE_PERSPECTIVE` as well.

### Castling Layers

The next four layers are dedicated to remaining castling permissions:

- Bottom Queen allowed
- Bottom King allowed
- Top Queen allowed
- Top King allowed

As for the piece position layers, `USE_PERSPECTIVE = 0` means bottom is white,
while `USE_PERSPECTIVE = 1` means bottom is the current player.

### Active Player Layer

This layer is only enable for `USE_PERSPECTIVE = 0`. It is fully set to 0, when
white is currently playing and fully set to 1, when black is currently playing.

### Must Lift Layer and Must Promote Layer

These two layers can either be fully 0 or fully 1. Each of them is only enabled,
when their respective flag `WITH_MUST_LIFT` or `WITH_MUST_PROMOTE` is enabled.

Depending on the `RequiredAction` from the current player, the values are

|Required Action   | Must Lift | Must Promote|
|------------------|-----------|-------------|
|Promote then Lift |         1 |            1|
|Lift              |         1 |            0|
|Place             |         0 |            0|
|Promote then Place|         0 |            1|
|Just Promote      |         0 |            1|

### No Progress Counter Layer

This layer is always used. It has a floating point value in [0.0, 1.0] depending
on the "no-progres half move counter".

## Index Representation

Transfering at least 8x8x30=1920 f32 to the GPU takes a bit of time. Not a lot,
but our Data is very sparse and we want to be able to transfer it more efficiently.

This is why we also have the index representation which is much more compact.

An Alpha-Zero style model can't operate directly on a dense index representation.
The index representation is always expanded to a tensor representation.

We have found massive performance improvements throught switching to the index
representation, especially when batching several model evaluations at once.

### Piece Position Indices

As there are always 32 pieces on the board, we can transmit the indices of the
pieces in the 8x8x24 initial tensor, each as a flattened u32 value.
This is 0 indexed.

### En Passant Index

There is a 33 index which is always present. If there is an en-passant square
to highlight, we take the flattened u32 index in the initial 8x8x25 tensor.

If there is no en-passant square, we just repeat the first piece position index.

This mean transforming the 33 first u32 values into the initial 8x8x25 tensor is
a single branchless operation.

### Castling Values

As Castling is represented by 4 full layers of 0 or 1 each, the index representation
reserves 4 u32 which store either 0 or 1. This is spread on the whole layer.

### Active Player Value

If `USE_PERSPECTIVE = 0`, then the index representation holds a 0 or 1 value for
the active player layer.

### Must Lift Value and Must Promote Value

- `WITH_MUST_LIFT` - Adds a value in {0, 1} that is used for a whole layer.
- `WITH_MUST_PROMOTE` - Adds a value in {0, 1} that is used for a whole layer.

### Half Move Clock Value

Takes a value from 0, 1, ..., 100 as u32. This is transformed into the half move
clock layer by dividing by 100.0 into a f32.

### Conversion Pseudocode

Here is the conversion pseudocode for the traditional `USE_PERSPECTIVE` representation.
Extend this as required when using arguments that add more constant layers.

```
tensor[indices[0:32]] = 1.0, where we index into tensor with the indices.
tensor[:,:,25] = indices[33] as f32         // Castling
tensor[:,:,26] = indices[34] as f32         // Castling
tensor[:,:,27] = indices[35] as f32         // Castling
tensor[:,:,28] = indices[36] as f32         // Castling
  // Extension goes here, changes subsequent indices.
tensor[:,:,29] = indices[37] as f32 / 100.0 // Half Move Clock
```

## Example

Here is the `USE_PERSPECTIVE` representation of the inital game state:

```
// Indices into the 8x8x25 initial tensor layers.
 64, 129, 194, 259, 324, 197, 134,  71,   8,   9,  10,
 11,  12,  13,  14,  15, 432, 433, 434, 435, 436, 437,
438, 439, 504, 569, 634, 699, 764, 637, 574, 511,  64,
// Castling
1, 1, 1, 1,
// Half Move Clock
0
```

Here is the `WITH_MUST_LIFT | WITH_MUST_PLACE` representation of the same:

```
// Indices into the 8x8x25 initial tensor layers.
 64, 129, 194, 259, 324, 197, 134,  71,   8,   9,  10,
 11,  12,  13,  14,  15, 432, 433, 434, 435, 436, 437,
438, 439, 504, 569, 634, 699, 764, 637, 574, 511,  64,
// Castling
1, 1, 1, 1,
// Current Player
0,
// Must Lift
1, 
// Must Place
0,
// Half Move Clock
0
```