#[path = "../native-support.rs"]
mod support;
unsafe extern "C" {
    #[link_name = "wasm.main"]
    fn initialize();
    #[link_name = "wasm.entry"]
    fn invoke(value: i32) -> i32;
}
#[unsafe(export_name = "builder_add")]
pub extern "C" fn builder_add(left: i32, right: i32) -> i32 {
    left + right
}

fn main() {
    support::initialize();
    unsafe { initialize() };
    for input in [-7, 0, 9, 42] {
        assert_eq!(unsafe { invoke(input) }, input * 3 + 20);
    }
    support::finish(0);
}
