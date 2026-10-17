//! Shared fixture setup uses the product runtime and the generated guest object.
#![allow(dead_code)]

unsafe extern "C" {
    fn native_module_init();
    fn atexit(callback: extern "C" fn()) -> i32;
}

// ---- Host arguments and completed resource cleanup ----

pub fn initialize() -> Vec<String> {
    let arguments: Vec<String> = std::env::args().collect();
    native_runtime::native::initialize_host();
    if arguments.get(1).is_some_and(|mode| mode == "exhaust") {
        unsafe { native_runtime::native::gc_test_limit_heap() };
    }
    unsafe { native_module_init() };
    arguments
}

pub fn finish(status: i32) -> ! {
    std::process::exit(native_runtime::native::native_finish(status));
}

extern "C" fn observe_cleanup() {
    if let Ok(path) = std::env::var("SNAIL_NATIVE_CLEANUP_LOG") {
        let count = native_runtime::native::native_resource_release_count();
        std::fs::write(path, format!("{count}\n")).unwrap();
    }
}

pub fn observe_releases() {
    assert_eq!(unsafe { atexit(observe_cleanup) }, 0);
}

pub fn number(text: &str) -> f64 {
    match text {
        "Infinity" => f64::INFINITY,
        "-Infinity" => f64::NEG_INFINITY,
        "NaN" => f64::NAN,
        _ => text.parse().unwrap(),
    }
}

pub fn same_float(actual: f64, expected: f64) -> bool {
    if expected.is_nan() {
        actual.is_nan()
    } else {
        actual == expected
            && (actual != 0.0 || actual.is_sign_negative() == expected.is_sign_negative())
    }
}
