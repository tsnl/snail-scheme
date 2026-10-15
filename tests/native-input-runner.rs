#[path = "native-support.rs"]
mod support;
unsafe extern "C" {
    #[link_name = "wasm.main"]
    fn main_entry();
    #[link_name = "wasm.copy-lines"]
    fn copy_lines() -> i64;
    #[link_name = "wasm.line-storage"]
    fn line_storage() -> i32;
    #[link_name = "wasm.close-input-alias"]
    fn close_alias();
    #[link_name = "wasm.input-callback-close"]
    fn callback_close() -> i64;
    #[link_name = "wasm.input-escaped-alias"]
    fn escaped_alias();
    #[link_name = "wasm.input-missing"]
    fn missing();
    #[link_name = "wasm.input-callback-trap"]
    fn callback_trap();
    #[link_name = "wasm.read-invalid"]
    fn read_invalid();
    #[link_name = "wasm.input-raw-output"]
    fn raw_output();
    #[link_name = "wasm.input-stale-handle"]
    fn stale_handle();
    #[link_name = "wasm.input-invalid-handle"]
    fn invalid_handle();
    #[link_name = "wasm.input-invalid-peek"]
    fn invalid_peek();
}

// ---- One process makes the same typed calls as the V8 input fixture ----

fn main() {
    support::observe_releases();
    let arguments = support::initialize();
    assert!(arguments.len() > 1);
    unsafe {
        main_entry();
        match arguments[1].as_str() {
            "copy" => assert_eq!(copy_lines(), arguments[2].parse::<i64>().unwrap()),
            "ownership" => {
                assert_ne!(line_storage(), 0);
                close_alias();
                assert_eq!(callback_close(), 19);
            }
            "alias" => escaped_alias(),
            "missing" => missing(),
            "trap" => callback_trap(),
            "invalid" => read_invalid(),
            "output" => raw_output(),
            "stale" => stale_handle(),
            "handle" => invalid_handle(),
            "peek" => invalid_peek(),
            _ => panic!("unknown input action"),
        }
    }
    support::finish(0);
}
