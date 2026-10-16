#[path = "../native-support.rs"]
mod support;
use std::sync::atomic::{AtomicI32, Ordering};
static COUNT: AtomicI32 = AtomicI32::new(0);
unsafe extern "C" {
    #[link_name = "wasm.main"]
    fn initialize();
    #[link_name = "wasm.entry"]
    fn invoke(value: i32) -> i32;
}
#[unsafe(export_name = "entry_tick")]
pub extern "C" fn entry_tick() -> i32 {
    COUNT.fetch_add(1, Ordering::SeqCst) + 1
}

fn main() {
    let arguments = support::initialize();
    assert_eq!(COUNT.load(Ordering::SeqCst), 0);
    if arguments.get(1).map(String::as_str) == Some("early") {
        support::finish(unsafe { invoke(1) });
    }
    unsafe { initialize() };
    assert_eq!(COUNT.load(Ordering::SeqCst), 1);
    assert_eq!((unsafe { invoke(1) }, unsafe { invoke(2) }), (42, 43));
    if arguments.get(1).map(String::as_str) == Some("repeat") {
        unsafe { initialize() };
    }
    assert_eq!(COUNT.load(Ordering::SeqCst), 1);
    support::finish(0);
}
