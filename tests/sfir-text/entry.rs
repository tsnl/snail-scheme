#[path = "../native-support.rs"]
mod support;
unsafe extern "C" {
    #[link_name = "wasm.main"]
    fn guest_main();
    #[link_name = "wasm.lower"]
    fn lower(p0: u32) -> u32;
    #[link_name = "wasm.alphabetic"]
    fn alphabetic(p0: u32) -> i32;
    #[link_name = "wasm.numeric"]
    fn numeric(p0: u32) -> i32;
    #[link_name = "wasm.whitespace"]
    fn whitespace(p0: u32) -> i32;
    #[link_name = "wasm.fresh-strings"]
    fn fresh_strings(p0: i64, p1: i64);
    #[link_name = "wasm.fill-left"]
    fn fill_left(p0: i64, p1: u32);
    #[link_name = "wasm.fill-right"]
    fn fill_right(p0: i64, p1: u32);
    #[link_name = "wasm.ordered"]
    fn ordered() -> i32;
    #[link_name = "wasm.self-ordered"]
    fn self_ordered() -> i32;
    #[link_name = "wasm.fold-left"]
    fn fold_left();
    #[link_name = "wasm.read-left"]
    fn read_left(p0: i64) -> u32;
    #[link_name = "wasm.read-right"]
    fn read_right(p0: i64) -> u32;
    #[link_name = "wasm.right-length"]
    fn right_length() -> i64;
    #[link_name = "wasm.same-strings"]
    fn same_strings() -> i32;
    #[link_name = "wasm.fold-literal"]
    fn fold_literal() -> i32;
    #[link_name = "wasm.fold-count"]
    fn fold_count(p0: u32) -> u32;
    #[link_name = "wasm.fold-component"]
    fn fold_component(p0: u32, p1: u32) -> u32;
    #[link_name = "wasm.malformed"]
    fn malformed(p0: i64, p1: i32);
}

// ---- Consume the same scalar corpus and mutable strings as V8 ----

fn records(name: &str) -> Vec<Vec<u32>> {
    std::fs::read_to_string(name)
        .unwrap()
        .lines()
        .map(|line| {
            line.split_whitespace()
                .map(|word| word.parse().unwrap())
                .collect()
        })
        .collect()
}

unsafe fn scalars() {
    for row in records("scalars.txt") {
        assert_eq!(row.len(), 5);
        let code = row[0];
        unsafe {
            println!(
                "{code} {} {} {} {}",
                lower(code),
                alphabetic(code),
                numeric(code),
                whitespace(code)
            );
        }
    }
}

unsafe fn strings() {
    unsafe {
        for row in records("strings.txt") {
            let a = row[0] as usize;
            let b = row[1] as usize;
            assert_eq!(row.len(), 3 + a + b);
            fresh_strings(a as i64, b as i64);
            for (index, code) in row[3..3 + a].iter().enumerate() {
                fill_left(index as i64, *code);
            }
            for (index, code) in row[3 + a..].iter().enumerate() {
                fill_right(index as i64, *code);
            }
            println!("{}", ordered());
            assert_eq!(self_ordered(), 0);
            assert_eq!(ordered(), row[2] as i32);
        }
        fresh_strings(1, 1);
        fill_left(0, 97);
        fill_right(0, 98);
        assert_ne!(ordered(), 0);
        fill_left(0, 99);
        assert_eq!(ordered(), 0);
        fill_left(0, 98);
        assert_eq!(ordered(), 0);
        fill_right(0, 99);
        assert_ne!(ordered(), 0);
    }
}

unsafe fn fold_scalars() {
    use std::io::BufRead;
    let input = std::io::BufReader::new(std::fs::File::open("fold-scalars.txt").unwrap());
    let mut count = 0;
    for line in input.lines() {
        let row: Vec<u32> = line
            .unwrap()
            .split_whitespace()
            .map(|word| word.parse().unwrap())
            .collect();
        assert_eq!(row.len(), 5);
        unsafe {
            assert_eq!(fold_count(row[0]), row[1]);
            for index in 0..row[1] {
                assert_eq!(fold_component(row[0], index), row[2 + index as usize]);
            }
        }
        count += 1;
    }
    println!("{count}");
}

unsafe fn check_folded_storage(source: &[u32], expected: &[u32]) {
    unsafe {
        fold_left();
        assert_eq!(right_length(), expected.len() as i64);
        assert_eq!(same_strings(), 0);
        for (index, code) in source.iter().enumerate() {
            assert_eq!(read_left(index as i64), *code);
        }
        for (index, code) in expected.iter().enumerate() {
            assert_eq!(read_right(index as i64), *code);
        }
        if !source.is_empty() {
            fill_left(0, 33);
            assert_eq!(read_right(0), expected[0]);
            fill_right(0, 63);
            assert_eq!(read_left(0), 33);
        }
    }
}

unsafe fn fold_strings() {
    let input = records("fold-strings.txt");
    unsafe {
        for row in &input {
            let size = row[0] as usize;
            let length = row[1] as usize;
            assert_eq!(row.len(), 2 + size + length);
            fresh_strings(size as i64, 0);
            for (index, code) in row[2..2 + size].iter().enumerate() {
                fill_left(index as i64, *code);
            }
            check_folded_storage(&row[2..2 + size], &row[2 + size..]);
        }
        assert_ne!(fold_literal(), 0);
    }
    println!("{}", input.len());
}

fn main() {
    support::observe_releases();
    let arguments = support::initialize();
    assert!(arguments.len() >= 2);
    unsafe {
        guest_main();
        match arguments[1].as_str() {
            "scalars" => scalars(),
            "strings" => strings(),
            "fold-scalars" => fold_scalars(),
            "fold-strings" => fold_strings(),
            _ => {
                assert_eq!(arguments.len(), 4);
                malformed(
                    arguments[2].parse().unwrap(),
                    arguments[3].parse::<u32>().unwrap() as i32,
                );
            }
        }
    }
    support::finish(0);
}
