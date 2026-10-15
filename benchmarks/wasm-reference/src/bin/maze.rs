// Derived from Olin Shivers's 1995 hexagonal maze and union/find benchmark.
// Copyright (c) 1995 by Olin Shivers.
use r7rs_wasm_reference::{Datum, input, report};
use std::fmt::{self, Display};
use std::hint::black_box;
use std::time::Instant;

// ---- Stable cell identities and disjoint reachable sets ----

struct Cell {
    set_parent: Option<usize>,
    size: usize,
    x: i64,
    y: i64,
    walls: i32,
    parent: Option<usize>,
    marked: bool,
}
struct Wall {
    owner: usize,
    neighbor: usize,
    bit: i32,
}
struct Maze {
    rows: usize,
    columns: usize,
    cells: Vec<Cell>,
}

impl Maze {
    fn new(rows: usize, columns: usize) -> Self {
        let cells = (0..rows * columns)
            .map(|id| Cell {
                set_parent: None,
                size: 1,
                x: (3 * (id % columns)) as i64,
                y: (2 * (id / columns) + (id % columns) % 2) as i64,
                walls: -1,
                parent: None,
                marked: false,
            })
            .collect();
        Self {
            rows,
            columns,
            cells,
        }
    }
    fn href(&self, x: i64, y: i64) -> usize {
        (y.div_euclid(2) as usize) * self.columns + x.div_euclid(3) as usize
    }
    fn root(&mut self, set: usize) -> usize {
        let mut root = set;
        while let Some(next) = self.cells[root].set_parent {
            root = next;
        }
        let mut node = set;
        while let Some(next) = self.cells[node].set_parent {
            if next == root {
                break;
            }
            self.cells[node].set_parent = Some(root);
            node = next;
        }
        root
    }
    fn union(&mut self, a: usize, b: usize) {
        let (a, b) = (self.root(a), self.root(b));
        let size = self.cells[a].size + self.cells[b].size;
        if self.cells[a].size > self.cells[b].size {
            self.cells[b].set_parent = Some(a);
            self.cells[a].size = size;
        } else {
            self.cells[a].set_parent = Some(b);
            self.cells[b].size = size;
        }
    }
    fn add_wall(&self, walls: &mut Vec<Wall>, x: i64, y: i64, nx: i64, ny: i64, bit: i32) {
        walls.push(Wall {
            owner: self.href(x, y),
            neighbor: self.href(nx, ny),
            bit,
        });
    }

    // Keep the exact construction order, including the special bottom row.
    // The source prepends walls before converting its list to a vector.
    fn wall_vector(&self) -> Vec<Wall> {
        let mut walls = Vec::new();
        let xmax = 3 * (self.columns - 1) as i64;
        for column in (0..self.columns).rev() {
            let x = 3 * column as i64;
            let mut y = 2 * (self.rows - 1) as i64 + (x & 1);
            while y > 1 {
                if x != 0 {
                    self.add_wall(&mut walls, x, y, x - 3, y - 1, 1);
                }
                self.add_wall(&mut walls, x, y, x, y - 2, 2);
                if x < xmax {
                    self.add_wall(&mut walls, x, y, x + 3, y - 1, 4);
                }
                y -= 2;
            }
        }
        if self.columns > 1 {
            let rightmost = 3 + 6 * (self.columns as i64 - 2).div_euclid(2);
            if rightmost < xmax {
                self.add_wall(&mut walls, rightmost, 1, xmax, 0, 4);
            }
            self.add_wall(&mut walls, rightmost, 1, rightmost - 3, 0, 1);
            let mut x = rightmost - 6;
            while x >= 3 {
                self.add_wall(&mut walls, x, 1, x - 3, 0, 1);
                self.add_wall(&mut walls, x, 1, x + 3, 0, 4);
                x -= 6;
            }
        }
        walls.reverse();
        walls
    }
    fn dig(&mut self, walls: &[Wall]) {
        for wall in walls.iter().rev() {
            if self.root(wall.owner) != self.root(wall.neighbor) {
                self.union(wall.owner, wall.neighbor);
                self.cells[wall.owner].walls &= !wall.bit;
                let root = self.root(wall.owner);
                if self.cells[root].size == self.cells.len() {
                    break;
                }
            }
        }
    }

    // Child order is SW, S, SE, NW, N, NE, as in the callback traversal.
    fn children(&self, node: usize) -> Vec<usize> {
        let cell = &self.cells[node];
        let (x, y, walls) = (cell.x, cell.y, cell.walls);
        let (maxx, maxy) = (3 * (self.columns - 1) as i64, 2 * (self.rows - 1) as i64);
        let mut children = Vec::new();
        if walls & 1 == 0 {
            children.push(self.href(x - 3, y - 1));
        }
        if walls & 2 == 0 {
            children.push(self.href(x, y - 2));
        }
        if walls & 4 == 0 {
            children.push(self.href(x + 3, y - 1));
        }
        if x > 0 && (y <= maxy || x % 6 == 0) {
            let nw = self.href(x - 3, y + 1);
            if self.cells[nw].walls & 4 == 0 {
                children.push(nw);
            }
        }
        if y < maxy {
            let north = self.href(x, y + 2);
            if self.cells[north].walls & 2 == 0 {
                children.push(north);
            }
        }
        if x < maxx && (y <= maxy || x % 6 == 0) {
            let ne = self.href(x + 3, y + 1);
            if self.cells[ne].walls & 1 == 0 {
                children.push(ne);
            }
        }
        children
    }
    fn dfs(&mut self, node: usize, parent: Option<usize>) {
        self.cells[node].parent = parent;
        for child in self.children(node) {
            if Some(child) != parent {
                self.dfs(child, Some(node));
            }
        }
    }
    fn reroot(&mut self, mut node: usize) {
        let mut parent = None;
        loop {
            let old = self.cells[node].parent;
            self.cells[node].parent = parent;
            match old {
                Some(next) => {
                    parent = Some(node);
                    node = next;
                }
                None => break,
            }
        }
    }
    fn path_length(&self, node: usize) -> usize {
        let (mut parent, mut length) = (self.cells[node].parent, 0);
        while let Some(node) = parent {
            length += 1;
            parent = self.cells[node].parent;
        }
        length
    }
    fn entrances(&mut self) -> (usize, usize) {
        self.dfs(0, None);
        let (mut maximum, mut entrance, mut exit) = (-1, 0, 0);
        for top in (0..self.columns).rev() {
            self.reroot((self.rows - 1) * self.columns + top);
            for bottom in (0..self.columns).rev() {
                let length = self.path_length(bottom) as i64;
                if length > maximum {
                    maximum = length;
                    entrance = top;
                    exit = bottom;
                }
            }
        }
        (entrance, exit)
    }
    fn mark_path(&mut self, mut node: usize) {
        loop {
            self.cells[node].marked = true;
            match self.cells[node].parent {
                Some(parent) => node = parent,
                None => break,
            }
        }
    }
}

// ---- Original Park-Miller variant and vector permutation ----

struct Random {
    seed: i64,
}
impl Random {
    fn integer(&mut self, n: usize) -> usize {
        let (hi, lo) = (self.seed.div_euclid(2787), self.seed.rem_euclid(2787));
        let test = 2813 * lo - 2699 * hi;
        self.seed = if test > 0 { test } else { test + 8388607 };
        self.seed.rem_euclid(n as i64) as usize
    }
}
fn permute(walls: &mut [Wall]) {
    let mut random = Random { seed: 20 };
    for i in (2..walls.len()).rev() {
        let j = random.integer(i);
        walls.swap(i, j);
    }
}
fn make_maze(rows: usize, columns: usize) -> (Maze, usize) {
    let mut maze = Maze::new(rows, columns);
    let mut walls = maze.wall_vector();
    permute(&mut walls);
    maze.dig(&walls);
    let (entrance, exit) = maze.entrances();
    maze.reroot((rows - 1) * columns + entrance);
    maze.mark_path(exit);
    maze.cells[exit].walls &= !2;
    (maze, entrance)
}

// ---- Owned character lists and iterative reclamation ----

struct Character {
    value: char,
    rest: Option<Box<Character>>,
}
#[derive(Default)]
struct Characters {
    first: Option<Box<Character>>,
}
impl Characters {
    fn prepend(&mut self, value: char) {
        self.first = Some(Box::new(Character {
            value,
            rest: self.first.take(),
        }));
    }
    fn reverse(&self) -> Self {
        let (mut result, mut rest) = (Self::default(), self.first.as_deref());
        while let Some(cell) = rest {
            result.prepend(cell.value);
            rest = cell.rest.as_deref();
        }
        result
    }
    fn parse(datum: &Datum) -> Self {
        let mut reversed = Self::default();
        for value in datum.list() {
            match value {
                Datum::Character(c) => reversed.prepend(*c),
                _ => panic!("expected character"),
            }
        }
        reversed.reverse()
    }
}
impl Drop for Characters {
    fn drop(&mut self) {
        let mut rest = self.first.take();
        while let Some(mut cell) = rest {
            rest = cell.rest.take();
        }
    }
}
impl PartialEq for Characters {
    fn eq(&self, other: &Self) -> bool {
        let (mut a, mut b) = (self.first.as_deref(), other.first.as_deref());
        loop {
            match (a, b) {
                (None, None) => return true,
                (Some(x), Some(y)) if x.value == y.value => {
                    a = x.rest.as_deref();
                    b = y.rest.as_deref();
                }
                _ => return false,
            }
        }
    }
}
impl Display for Characters {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        let mut rest = self.first.as_deref();
        write!(out, "(")?;
        while let Some(cell) = rest {
            match cell.value {
                ' ' => write!(out, "#\\space")?,
                '\n' => write!(out, "#\\newline")?,
                c => write!(out, "#\\{c}")?,
            }
            if cell.rest.is_some() {
                write!(out, " ")?;
            }
            rest = cell.rest.as_deref();
        }
        write!(out, ")")
    }
}

// ---- Original hexagonal character rendering ----

struct Printer {
    output: Characters,
}
impl Printer {
    fn bottom(&mut self, walls: i32) {
        self.output.prepend(if walls & 1 != 0 { '\\' } else { ' ' });
        self.output.prepend(if walls & 2 != 0 { '_' } else { ' ' });
        self.output.prepend(if walls & 4 != 0 { '/' } else { ' ' });
    }
    fn dot(&mut self, maze: &Maze, row: i64, column: usize) {
        self.output.prepend(
            if row >= 0 && maze.cells[row as usize * maze.columns + column].marked {
                '.'
            } else {
                ' '
            },
        );
    }
    fn render(&mut self, maze: &Maze, entrance: usize) {
        let ncols2 = 2 * (maze.columns / 2);
        for column in (1..maze.columns).step_by(2) {
            for _ in 0..3 {
                self.output.prepend(' ');
            }
            self.output
                .prepend(if column == entrance { ' ' } else { '_' });
        }
        self.output.prepend('\n');
        self.output.prepend(' ');
        for column in (0..ncols2).step_by(2) {
            self.output
                .prepend(if column == entrance { ' ' } else { '_' });
            self.output.prepend('/');
            self.dot(maze, maze.rows as i64 - 1, column + 1);
            self.output.prepend('\\');
        }
        if maze.columns % 2 == 1 {
            self.output.prepend(if entrance == maze.columns - 1 {
                ' '
            } else {
                '_'
            });
        }
        self.output.prepend('\n');
        for row in (0..maze.rows).rev() {
            self.output.prepend('/');
            for column in (1..ncols2).step_by(2) {
                self.dot(maze, row as i64, column - 1);
                self.bottom(maze.cells[row * maze.columns + column].walls);
            }
            if maze.columns % 2 == 1 {
                self.dot(maze, row as i64, maze.columns - 1);
                self.output.prepend('\\');
            }
            self.output.prepend('\n');
            for column in (0..ncols2).step_by(2) {
                self.bottom(maze.cells[row * maze.columns + column].walls);
                self.dot(maze, row as i64 - 1, column + 1);
            }
            if maze.columns % 2 == 1 {
                self.bottom(maze.cells[row * maze.columns + maze.columns - 1].walls);
            } else if row != 0 {
                self.output.prepend('\\');
            }
            self.output.prepend('\n');
        }
    }
    fn run(&mut self, rows: usize, columns: usize) -> Characters {
        self.output = Characters::default();
        let (maze, entrance) = make_maze(rows, columns);
        self.render(&maze, entrance);
        self.output.reverse()
    }
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, rows, columns) = (values[0].number(), values[1].number(), values[2].number());
    let expected = Characters::parse(&values[3]);
    let mut printer = Printer {
        output: Characters::default(),
    };
    let (start, mut result) = (Instant::now(), Characters::default());
    for _ in 0..count {
        result = black_box(printer.run(black_box(rows), black_box(columns)));
    }
    assert!(result == expected);
    report("maze", count, start, &result);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn union_root_identity_and_path_compression() {
        let mut maze = Maze::new(2, 2);
        maze.union(0, 1);
        maze.union(2, 3);
        maze.union(1, 3);
        assert_eq!(maze.root(0), maze.root(2));
        let root = maze.root(0);
        assert_eq!(maze.cells[root].size, 4);
    }
    #[test]
    fn generated_maze_is_a_spanning_tree_and_marked_route() {
        let (maze, _) = make_maze(3, 3);
        assert!(maze.cells.iter().any(|c| c.marked));
        assert!(maze.cells.iter().all(|c| c.size >= 1));
        assert_eq!(maze.cells.iter().filter(|c| c.parent.is_some()).count(), 8);
    }
}
