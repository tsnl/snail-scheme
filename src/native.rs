//! Terminal native invocation cleanup. No operation here calls Scheme.
//! Resource services end their borrow before any guest allocation or callback.

use std::cell::Cell;

unsafe extern "C" {
    fn native_report_error(pointer: *const u8, length: usize) -> !;
    fn native_finish(status: i32) -> i32;
    fn native_resource_released();
    fn native_array_released();
}

thread_local! {
    static TERMINATED: Cell<bool> = const { Cell::new(false) };
    static LEGACY_CLEANUP: Cell<Option<fn() -> bool>> = const { Cell::new(None) };
}

pub(crate) fn register_legacy_cleanup(cleanup: fn() -> bool) {
    LEGACY_CLEANUP.set(Some(cleanup));
}

pub(crate) fn report_error(message: &str) -> ! {
    unsafe { native_report_error(message.as_ptr(), message.len()) }
}

pub(crate) fn exit(status: i32) -> ! {
    std::process::exit(unsafe { native_finish(status) })
}

pub(crate) fn resource_released() {
    unsafe { native_resource_released() };
}

pub(crate) fn array_released() {
    unsafe { native_array_released() };
}

#[unsafe(no_mangle)]
pub extern "C" fn snail_native_cleanup() -> i32 {
    if TERMINATED.replace(true) {
        return 0;
    }
    let strict = crate::strict_io::close_all();
    let legacy = LEGACY_CLEANUP.get().is_some_and(|cleanup| cleanup());
    crate::iverson::close_all_native();
    i32::from(strict != 0 || legacy)
}
