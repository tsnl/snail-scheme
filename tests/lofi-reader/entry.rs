#[path = "../native-support.rs"]
mod support;
unsafe extern "C" {
    #[link_name = "wasm.main"]
    fn guest_main();
    #[link_name = "wasm.check"]
    fn check() -> i64;
    #[link_name = "wasm.storage"]
    fn storage() -> i32;
    #[link_name = "wasm.scan"]
    fn scan() -> i64;
}

// ---- Initialize one native module and consume its complete stream ----

fn main() {
    support::initialize();
    unsafe {
        guest_main();
        assert_eq!(check(), 42);
        assert_ne!(storage(), 0);
        println!("result:{}", scan());
    }
    support::finish(0);
}
