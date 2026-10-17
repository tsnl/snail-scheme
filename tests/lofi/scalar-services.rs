#[path = "../native-support.rs"]
mod support;
unsafe extern "C" {
    #[link_name = "wasm.main"]
    fn guest_main();
    #[link_name = "wasm.unary"]
    fn unary(p0: i64, p1: f64) -> f64;
    #[link_name = "wasm.binary"]
    fn binary(p0: i64, p1: f64, p2: f64) -> f64;
    #[link_name = "wasm.character"]
    fn character(p0: i64, p1: u32) -> i64;
}

// ---- Call the same typed exports through their native scalar signatures ----

fn main() {
    let arguments = support::initialize();
    unsafe { guest_main() };
    assert_eq!((arguments.len() - 1) % 4, 0);
    for values in arguments[1..].chunks_exact(4) {
        let operation = values[1].parse().unwrap();
        let left = support::number(&values[2]);
        let right = support::number(&values[3]);
        let result = unsafe {
            match values[0].as_str() {
                "unary" => unary(operation, left),
                "binary" => binary(operation, left, right),
                "character" => character(operation, left as u32) as f64,
                _ => panic!("unknown scalar action"),
            }
        };
        println!("{result:.17e}");
    }
    support::finish(0);
}
