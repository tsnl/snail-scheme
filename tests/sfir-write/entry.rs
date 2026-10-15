#[path = "../native-support.rs"]
mod support;
unsafe extern "C" {
    #[link_name = "wasm.main"]
    fn guest_main();
    #[link_name = "wasm.copy-output"]
    fn copy_output() -> i64;
    #[link_name = "wasm.roundtrip"]
    fn roundtrip() -> i32;
    #[link_name = "wasm.graphs"]
    fn graphs();
    #[link_name = "wasm.deep-output"]
    fn deep_output();
    #[link_name = "wasm.stdout-check"]
    fn stdout_check();
    #[link_name = "wasm.closed-empty"]
    fn closed_empty();
    #[link_name = "wasm.callback-trap"]
    fn callback_trap();
    #[link_name = "wasm.invalid-character"]
    fn invalid_character();
    #[link_name = "wasm.invalid-handle"]
    fn invalid_handle();
    #[link_name = "wasm.read-stdout"]
    fn read_stdout();
    #[link_name = "wasm.stdout-failure"]
    fn stdout_failure();
}

// ---- Native execution uses the same named guest exports as V8 ----

fn main() {
    support::observe_releases();
    let arguments = support::initialize();
    assert_eq!(arguments.len(), 2);
    unsafe {
        guest_main();
        match arguments[1].as_str() {
            "stream" => {
                assert!(copy_output() > 0);
                assert_ne!(roundtrip(), 0);
            }
            "graphs" => graphs(),
            "deep" => deep_output(),
            "stdout" => stdout_check(),
            "closed" => closed_empty(),
            "trap" => callback_trap(),
            "character" => invalid_character(),
            "handle" => invalid_handle(),
            "read-stdout" => read_stdout(),
            "stdout-failure" => {
                use std::os::fd::AsRawFd;
                unsafe extern "C" {
                    fn dup2(source: i32, destination: i32) -> i32;
                }
                let file = std::fs::OpenOptions::new()
                    .write(true)
                    .open("/dev/full")
                    .unwrap();
                assert_eq!(dup2(file.as_raw_fd(), 1), 1);
                stdout_failure();
            }
            _ => panic!("unknown writer action"),
        }
    }
    support::finish(0);
}
