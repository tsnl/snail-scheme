#[path = "native-support.rs"]
mod support;
unsafe extern "C" {
    #[link_name = "wasm.format-number"]
    fn format_number(p0: i64) -> i64;
    #[link_name = "wasm.unicode"]
    fn unicode() -> i64;
    #[link_name = "wasm.callback-result"]
    fn callback_result() -> f64;
    #[link_name = "wasm.exists"]
    fn exists() -> i32;
    #[link_name = "wasm.remove"]
    fn remove_file();
    #[link_name = "wasm.callback-trap"]
    fn callback_trap();
    #[link_name = "wasm.close-failure"]
    fn close_failure();
    #[link_name = "wasm.missing-directory"]
    fn missing_directory();
    #[link_name = "wasm.invalid-character"]
    fn invalid_character();
    #[link_name = "wasm.invalid-handle"]
    fn invalid_handle();
    #[link_name = "wasm.escaped-alias"]
    fn escaped_alias();
    #[link_name = "wasm.close-alias"]
    fn close_alias();
    #[link_name = "wasm.main"]
    fn main_entry();
}

// ---- Observe actual resources on normal and terminal native execution ----

fn main() {
    support::observe_releases();
    let arguments = support::initialize();
    unsafe {
        main_entry();
        match arguments.get(1).map(String::as_str) {
            Some("unicode") => assert_eq!(unicode(), 42),
            Some("trap") => callback_trap(),
            Some("io-error") => close_failure(),
            Some("missing") => missing_directory(),
            Some("character") => invalid_character(),
            Some("handle") => invalid_handle(),
            Some("alias") => escaped_alias(),
            Some("number") => {
                let value = arguments[2].parse().unwrap();
                assert_eq!(format_number(value), value);
            }
            _ => {
                assert_eq!(unicode(), 42);
                assert_ne!(exists(), 0);
                assert_eq!(callback_result(), 1.25);
                close_alias();
                remove_file();
                assert_eq!(exists(), 0);
            }
        }
    }
    support::finish(0);
}
