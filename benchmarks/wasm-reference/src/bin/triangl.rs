use r7rs_wasm_reference::{Datum, input, report};
use std::hint::black_box;
use std::time::Instant;

// ---- Triangle board moves ----

const A: [usize; 37] = [
    1, 2, 4, 3, 5, 6, 1, 3, 6, 2, 5, 4, 11, 12, 13, 7, 8, 4, 4, 7, 11, 8, 12, 13, 6, 10, 15, 9, 14,
    13, 13, 14, 15, 9, 10, 6, 6,
];
const B: [usize; 37] = [
    2, 4, 7, 5, 8, 9, 3, 6, 10, 5, 9, 8, 12, 13, 14, 8, 9, 5, 2, 4, 7, 5, 8, 9, 3, 6, 10, 5, 9, 8,
    12, 13, 14, 8, 9, 5, 5,
];
const C: [usize; 37] = [
    4, 7, 11, 8, 12, 13, 6, 10, 15, 9, 14, 13, 13, 14, 15, 9, 10, 6, 1, 2, 4, 3, 5, 6, 1, 3, 6, 2,
    5, 4, 11, 12, 13, 7, 8, 4, 4,
];

struct Game {
    board: [u8; 16],
    sequence: [usize; 14],
    answers: Vec<Vec<usize>>,
}

impl Game {
    fn new() -> Self {
        Self {
            board: [1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
            sequence: [0; 14],
            answers: Vec::new(),
        }
    }
    fn attempt(&mut self, movement: usize, depth: usize) -> bool {
        if depth == 14 {
            self.answers.push(self.sequence[1..].to_vec());
            return true;
        }
        let (a, b, c) = (A[movement], B[movement], C[movement]);
        if self.board[a] != 1 || self.board[b] != 1 || self.board[c] != 0 {
            return false;
        }
        (self.board[a], self.board[b], self.board[c]) = (0, 0, 1);
        self.sequence[depth] = movement;
        for next in 0..36 {
            if self.attempt(next, depth + 1) {
                break;
            }
        }
        (self.board[a], self.board[b], self.board[c]) = (1, 1, 0);
        false
    }
    fn run(&mut self, movement: usize, depth: usize) -> Vec<usize> {
        self.answers.clear();
        self.attempt(movement, depth);
        self.answers.last().expect("no solution").clone()
    }
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, movement, depth) = (values[0].number(), values[1].number(), values[2].number());
    let expected: Vec<_> = values[3].list().iter().map(Datum::number).collect();
    let mut game = Game::new();
    let (start, mut result) = (Instant::now(), Vec::new());
    for _ in 0..count {
        result = black_box(game.run(black_box(movement), black_box(depth)));
    }
    assert_eq!(result, expected);
    report(
        "triangl",
        count,
        start,
        Datum::List(result.iter().map(|n| Datum::Atom(n.to_string())).collect()),
    );
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn full_solution_and_board_restoration() {
        let mut game = Game::new();
        let original = game.board;
        assert_eq!(
            game.run(22, 1),
            vec![22, 34, 31, 15, 7, 1, 20, 17, 25, 6, 5, 13, 32]
        );
        assert_eq!(game.board, original);
    }
}
