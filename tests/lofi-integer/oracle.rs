#[path = "../native-support.rs"]
mod support;
unsafe extern "Rust" {
    fn oracle_arguments(left: &str, right: &str);
    fn oracle_output() -> String;
}
unsafe extern "C" {
    #[link_name = "wasm.main"]
    fn guest_main();
    #[link_name = "wasm.integer-probe"]
    fn integer_probe(operation: i64) -> i64;
}

// ---- Every valid case compares its entire decimal result ----

fn main() {
    let arguments = support::initialize();
    assert_eq!(arguments.len(), 2);
    unsafe { guest_main() };
    let input = std::fs::read_to_string(&arguments[1]).unwrap();
    for (index, line) in input.lines().enumerate() {
        let field: Vec<&str> = line.split('\t').collect();
        assert_eq!(field.len(), 4);
        unsafe { oracle_arguments(field[1], field[2]) };
        assert_eq!(unsafe { integer_probe(field[0].parse().unwrap()) }, 1);
        assert_eq!(
            unsafe { oracle_output() }.as_str(),
            field[3],
            "case {index}"
        );
    }
    println!("cases {} passed", input.lines().count());
    support::finish(0);
}
