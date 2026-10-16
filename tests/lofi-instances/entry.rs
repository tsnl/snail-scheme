#[path = "../native-support.rs"]
mod support;
unsafe extern "C" {
    #[link_name = "wasm.main"]
    fn guest_main() -> i64;
}

fn main() {
    support::initialize();
    assert_eq!(unsafe { guest_main() }, 42);
    support::finish(0);
}
