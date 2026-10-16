#[path = "../native-support.rs"]
mod support;
unsafe extern "Rust" {
    fn oracle_arguments(left: &str, right: &str);
    fn oracle_output() -> String;
}
unsafe extern "C" {
    #[link_name = "wasm.main"]
    fn guest_main();
    #[link_name = "wasm.probe"]
    fn probe(operation: i64, input: f64) -> f64;
}

// ---- Compare full exact strings and every binary64 result bit ----

fn main() {
    let arguments = support::initialize();
    assert_eq!(arguments.len(), 2);
    unsafe { guest_main() };
    let input = std::fs::read_to_string(&arguments[1]).unwrap();
    for (index, line) in input.lines().enumerate() {
        let field: Vec<&str> = line.split('\t').collect();
        assert_eq!(field.len(), 6);
        unsafe { oracle_arguments(field[1], field[2]) };
        let value = f64::from_bits(field[3].parse().unwrap());
        let actual = unsafe { probe(field[0].parse().unwrap(), value) };
        assert_eq!(
            actual.to_bits(),
            field[4].parse::<u64>().unwrap(),
            "case {index}"
        );
        assert_eq!(
            unsafe { oracle_output() }.as_str(),
            field[5],
            "case {index}"
        );
    }
    println!("cases {} passed", input.lines().count());
    support::finish(0);
}
