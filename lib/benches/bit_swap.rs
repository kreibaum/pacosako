use criterion::{criterion_group, criterion_main, BatchSize, Criterion};
use pacosako::substrate::BitBoard;
use pacosako::BoardPosition;
use rand::rngs::StdRng;
use rand::{Rng, SeedableRng};
use std::hint::black_box;

// XOR-based bit swap
fn xor_swap(board: &mut BitBoard, a: BoardPosition, b: BoardPosition) {
    let pos_a = a.0;
    let pos_b = b.0;
    let diff = ((board.0 >> pos_a) ^ (board.0 >> pos_b)) & 1;
    let mask = (diff << pos_a) | (diff << pos_b);
    board.0 ^= mask;
}

// Mask-based bit swap
fn mask_swap(board: &mut BitBoard, a: BoardPosition, b: BoardPosition) {
    let pos_a = a.0;
    let pos_b = b.0;
    let bit_a = (board.0 >> pos_a) & 1;
    let bit_b = (board.0 >> pos_b) & 1;
    board.0 &= !(1 << pos_a);
    board.0 &= !(1 << pos_b);
    board.0 |= bit_a << pos_b;
    board.0 |= bit_b << pos_a;
}

fn generate_boards(n: usize, seed: u64) -> Vec<BitBoard> {
    let mut rng = StdRng::from_seed([
        1, 172, 195, 43, 53, 112, 131, 29, 204, 158, 133, 5, 71, 71, 145, 82, 253, 44, 222, 28,
        244, 48, 73, 245, 220, 102, 21, 114, 215, 141, 19, 198,
    ]);
    (0..n).map(|_| BitBoard(rng.gen())).collect()
}

// Criterion benchmark
fn bench_bit_swaps(c: &mut Criterion) {
    let a = BoardPosition(17);
    let b = BoardPosition(9);
    let boards = generate_boards(10_000, 42); // Generate 10,000 random boards with a fixed seed

    c.bench_function("xor_swap", |bencher| {
        bencher.iter_batched(
            || boards.clone(),
            |batch| {
                for mut board in batch {
                    xor_swap(black_box(&mut board), a, b);
                }
            },
            BatchSize::SmallInput,
        )
    });

    c.bench_function("mask_swap", |bencher| {
        bencher.iter_batched(
            || boards.clone(),
            |batch| {
                for mut board in batch {
                    mask_swap(black_box(&mut board), a, b);
                }
            },
            BatchSize::SmallInput,
        )
    });
}

criterion_group!(benches, bench_bit_swaps);
criterion_main!(benches);
