//! Scalar host services linked into Snail-Core's Wasm programs.
//!
//! Managed values remain in compiled Snail-Core. Rust owns streams behind scalar
//! IDs and synchronous text-conversion and path-reply scratch; it never holds
//! guest GC roots.

// Ordinary cargo tests exercise helpers independently of a Wasm engine.
#![cfg_attr(not(target_arch = "wasm32"), allow(dead_code))]

mod datum;
mod host;
mod io;
mod math;
mod paths;
mod text;
mod unicode;

// ---- Module initialization ----

// Export a reactor initializer so wasm-ld does not wrap each exported function
// in constructor/destructor calls. The linked Wasm entry calls it once, before
// Snail-Core or Rust runs. All callable Rust services share this runtime.
#[cfg(target_arch = "wasm32")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn _initialize() {
    unsafe extern "C" {
        fn __wasm_call_ctors();
    }
    unsafe { __wasm_call_ctors() };
}

// ---- Terminal diagnostics ----

fn fail_message(message: &str) -> ! {
    #[cfg(target_arch = "wasm32")]
    unsafe {
        #[link(wasm_import_module = "snail.platform")]
        unsafe extern "C" {
            #[link_name = "diagnostics/report-error"]
            fn report_error(pointer: *const u8, length: usize) -> !;
        }
        report_error(message.as_ptr(), message.len())
    }
    #[cfg(all(not(target_arch = "wasm32"), not(test)))]
    {
        eprintln!("snail: {message}");
        io::close_all();
        std::process::exit(1)
    }
    #[cfg(all(not(target_arch = "wasm32"), test))]
    panic!("snail: {message}")
}

/// Print a diagnostic borrowed from the linked runtime's shared linear memory.
///
/// # Safety
/// The pointer must identify `length` readable bytes for the duration of this call.
#[unsafe(export_name = "snail:report-error")]
pub unsafe extern "C" fn report_error(pointer: *const u8, length: usize) {
    let bytes = unsafe { std::slice::from_raw_parts(pointer, length) };
    eprintln!("snail: {}", String::from_utf8_lossy(bytes));
    std::process::exit(1)
}

// ---- Guest panics ----

thread_local! {
    static PANIC_MESSAGE: std::cell::RefCell<String> = const { std::cell::RefCell::new(String::new()) };
}

/// Append one Unicode scalar to the pending panic message.
#[unsafe(export_name = "snail:panic/character")]
pub extern "C" fn panic_character(code: u32) {
    let character = char::from_u32(code).unwrap_or(char::REPLACEMENT_CHARACTER);
    PANIC_MESSAGE.with_borrow_mut(|message| message.push(character));
}

/// Release files, flushing buffered output, then report the message and stop.
#[unsafe(export_name = "snail:panic/raise")]
pub extern "C" fn panic_raise() {
    let message = PANIC_MESSAGE.with_borrow_mut(std::mem::take);
    io::close_all();
    fail_message(&message)
}

// ---- Monotonic clock ----

thread_local! {
    static ORIGIN: std::cell::OnceCell<std::time::Instant> = const { std::cell::OnceCell::new() };
}

/// Nanoseconds since the instance first read this clock, through WASI's
/// monotonic `clock_time_get`. Only differences mean anything, and later
/// readings are never smaller.
#[unsafe(export_name = "snail:clock/monotonic")]
pub extern "C" fn monotonic() -> i64 {
    let elapsed = ORIGIN.with(|origin| origin.get_or_init(std::time::Instant::now).elapsed());
    i64::try_from(elapsed.as_nanos()).unwrap_or(i64::MAX)
}

// ---- Floating-point text ----

fn parse_float(text: &str) -> Option<f64> {
    if text.eq_ignore_ascii_case("+inf.0") {
        Some(f64::INFINITY)
    } else if text.eq_ignore_ascii_case("-inf.0") {
        Some(f64::NEG_INFINITY)
    } else if text.eq_ignore_ascii_case("+nan.0") || text.eq_ignore_ascii_case("-nan.0") {
        Some(f64::NAN)
    } else if text.contains(['.', 'e', 'E']) {
        text.parse().ok()
    } else {
        None
    }
}

fn float_text(number: f64) -> String {
    if number.is_nan() {
        "+nan.0".into()
    } else if number == f64::INFINITY {
        "+inf.0".into()
    } else if number == f64::NEG_INFINITY {
        "-inf.0".into()
    } else {
        finite_float_text(number)
    }
}

fn finite_float_text(number: f64) -> String {
    let mut text = format!("{number:?}");
    // Match the bootstrap writer's explicit positive exponent. Both spellings
    // read identically, but compiler output is compared byte for byte.
    if let Some(index) = text.find('e') {
        if text.as_bytes()[index + 1] != b'-' {
            text.insert(index + 1, '+');
        }
    }
    text
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn floating_text_preserves_sign_exponents_and_nonfinite_values() {
        assert_eq!(float_text(-0.0), "-0.0");
        assert_eq!(float_text(f64::INFINITY), "+inf.0");
        assert_eq!(float_text(9.223372036854776e18), "9.223372036854776e+18");
        assert_eq!(float_text(1.25e-18), "1.25e-18");
        assert!(parse_float("+nan.0").unwrap().is_nan());
        assert_eq!(parse_float("3"), None);
        assert_eq!(parse_float("3.5"), Some(3.5));
        assert_eq!(parse_float("+INF.0"), Some(f64::INFINITY));
    }

    #[test]
    fn the_monotonic_clock_starts_near_zero_and_never_runs_back() {
        let first = monotonic();
        let second = monotonic();
        assert!((0..1_000_000_000).contains(&first));
        assert!(second >= first);
    }
}
