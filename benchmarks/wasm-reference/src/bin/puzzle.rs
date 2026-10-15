use r7rs_wasm_reference::{input, report};
use std::hint::black_box;
use std::time::Instant;

// ---- Mutable puzzle and piece templates ----

struct Puzzle {
    board: Vec<bool>,
    pieces: Vec<Vec<bool>>,
    classes: [usize; 13],
    maxima: [usize; 13],
    counts: [usize; 4],
    trials: usize,
    size: usize,
}

impl Puzzle {
    fn new() -> Self {
        Self {
            board: vec![true; 512],
            pieces: vec![vec![false; 512]; 13],
            classes: [0; 13],
            maxima: [0; 13],
            counts: [0; 4],
            trials: 0,
            size: 511,
        }
    }

    fn define_piece(&mut self, piece: usize, class: usize, dimensions: (usize, usize, usize)) {
        let (ii, jj, kk) = dimensions;
        for i in 0..=ii {
            for j in 0..=jj {
                for k in 0..=kk {
                    let index = i + 8 * (j + 8 * k);
                    self.pieces[piece][index] = true;
                    self.maxima[piece] = index;
                }
            }
        }
        self.classes[piece] = class;
    }

    fn reset(&mut self, size: usize) {
        self.size = size;
        self.trials = 0;
        self.board[..=size].fill(true);
        for i in 1..=5 {
            for j in 1..=5 {
                for k in 1..=5 {
                    self.board[i + 8 * (j + 8 * k)] = false;
                }
            }
        }
        for piece in &mut self.pieces {
            piece[..=size].fill(false);
        }
        let shapes = [
            (0, (3, 1, 0)),
            (0, (1, 0, 3)),
            (0, (0, 3, 1)),
            (0, (1, 3, 0)),
            (0, (3, 0, 1)),
            (0, (0, 1, 3)),
            (1, (2, 0, 0)),
            (1, (0, 2, 0)),
            (1, (0, 0, 2)),
            (2, (1, 1, 0)),
            (2, (1, 0, 1)),
            (2, (0, 1, 1)),
            (3, (1, 1, 1)),
        ];
        for (piece, &(class, dimensions)) in shapes.iter().enumerate() {
            self.define_piece(piece, class, dimensions);
        }
        self.counts = [13, 3, 1, 1];
    }

    fn fits(&self, piece: usize, position: usize) -> bool {
        (0..=self.maxima[piece]).all(|k| !self.pieces[piece][k] || !self.board[position + k])
    }

    fn place(&mut self, piece: usize, position: usize) -> usize {
        for k in 0..=self.maxima[piece] {
            if self.pieces[piece][k] {
                self.board[position + k] = true;
            }
        }
        self.counts[self.classes[piece]] -= 1;
        (position..=self.size)
            .find(|&k| !self.board[k])
            .unwrap_or(0)
    }

    fn remove(&mut self, piece: usize, position: usize) {
        for k in 0..=self.maxima[piece] {
            if self.pieces[piece][k] {
                self.board[position + k] = false;
            }
        }
        self.counts[self.classes[piece]] += 1;
    }

    fn trial(&mut self, position: usize) -> bool {
        for piece in 0..13 {
            if self.counts[self.classes[piece]] != 0 && self.fits(piece, position) {
                let next = self.place(piece, position);
                // The original tries position zero before recognizing completion.
                if self.trial(next) || next == 0 {
                    self.trials += 1;
                    return true;
                }
                self.remove(piece, position);
            }
        }
        self.trials += 1;
        false
    }

    fn run(&mut self, size: usize) -> usize {
        self.reset(size);
        assert!(self.fits(0, 73));
        let next = self.place(0, 73);
        assert!(self.trial(next));
        self.trials
    }
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, size) = (values[0].number(), values[1].number());
    let mut puzzle = Puzzle::new();
    let (start, mut result) = (Instant::now(), 0);
    for _ in 0..count {
        result = black_box(puzzle.run(black_box(size)));
    }
    assert_eq!(result, values[2].number());
    report("puzzle", count, start, result);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn search_count_and_complete_filled_board() {
        let mut puzzle = Puzzle::new();
        assert_eq!(puzzle.run(511), 2005);
        assert!(puzzle.board.iter().all(|&occupied| occupied));
        assert_eq!(puzzle.counts, [0; 4]);
        assert_eq!(puzzle.run(511), 2005);
    }
}
