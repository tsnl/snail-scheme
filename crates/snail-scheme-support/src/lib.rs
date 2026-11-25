//! Scalar host services linked into `snail-scheme`'s Wasm programs.
//!
//! The linked heap owns shared objects and published roots. Streams and path
//! replies belong to their scalar services, with explicit resource lifetimes.

// Ordinary cargo tests exercise helpers independently of a Wasm engine.
#![cfg_attr(not(target_arch = "wasm32"), allow(dead_code))]

#[cfg(feature = "assembler")]
pub mod assembler;
mod heap;
mod host;
mod io;
mod paths;

// ---- Module initialization ----

// Export a reactor initializer so wasm-ld does not wrap each exported function
// in constructor/destructor calls. The linked Wasm entry calls it once, before
// `snail-scheme` or Rust runs. All callable Rust services share this runtime.
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

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_monotonic_clock_starts_near_zero_and_never_runs_back() {
        let first = monotonic();
        let second = monotonic();
        assert!((0..1_000_000_000).contains(&first));
        assert!(second >= first);
    }
}
