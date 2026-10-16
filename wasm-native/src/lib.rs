//! Scalar host services shared by Lofi's Wasm and native targets.
//!
//! Managed values remain in compiled Lofi. Rust owns streams, temporary token
//! text and stable symbol names behind scalar IDs; it never holds guest GC roots.

// Ordinary cargo tests exercise helpers independently of a Wasm engine.
#![cfg_attr(not(target_arch = "wasm32"), allow(dead_code))]

#[cfg(all(
    feature = "native-runtime",
    not(target_arch = "wasm32"),
    not(all(target_arch = "x86_64", target_os = "linux"))
))]
compile_error!("the native runtime currently requires x86-64 Linux");

mod host;
#[cfg(all(
    target_arch = "x86_64",
    target_os = "linux",
    any(feature = "native-runtime", test)
))]
pub mod native;
#[cfg(all(
    target_arch = "x86_64",
    target_os = "linux",
    any(feature = "native-runtime", test)
))]
mod native_gc;
mod strict_datum;
mod strict_io;
mod strict_math;
mod strict_number;
mod strict_text;
mod symbols;
mod unicode;

// ---- Module initialization ----

// Export a reactor initializer so wasm-ld does not wrap each exported function
// in constructor/destructor calls. The linked Wasm entry calls it once, before
// Lofi or Rust runs. All callable Rust services share this runtime.
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
    #[cfg(all(feature = "native-runtime", not(target_arch = "wasm32"), not(test)))]
    native::report_error(message);
    #[cfg(all(
        not(target_arch = "wasm32"),
        any(not(feature = "native-runtime"), test)
    ))]
    panic!("snail-lofi: {message}")
}

/// Print a diagnostic borrowed from the linked runtime's shared linear memory.
///
/// # Safety
/// The pointer must identify `length` readable bytes for the duration of this call.
#[unsafe(export_name = "snail:report-error")]
pub unsafe extern "C" fn report_error(pointer: *const u8, length: usize) {
    let bytes = unsafe { std::slice::from_raw_parts(pointer, length) };
    eprintln!("snail-lofi: {}", String::from_utf8_lossy(bytes));
    std::process::exit(1)
}

// ---- Floating-point text shared by scalar token services ----

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
}
