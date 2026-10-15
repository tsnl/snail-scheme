#[path = "native-support.rs"]
mod support;
unsafe extern "C" {
    #[link_name = "wasm.main"]
    fn guest_main();
    #[link_name = "wasm.trigonometry"]
    fn trigonometry(p0: i64, p1: f64) -> f64;
}

// ---- The same compiled worker calls the shared Rust scalar service ----

fn main() {
    let arguments = support::initialize();
    unsafe { guest_main() };
    for text in &arguments[1..] {
        for operation in 0..3 {
            println!("{:.17e}", unsafe {
                trigonometry(operation, support::number(text))
            });
        }
    }
    support::finish(0);
}
