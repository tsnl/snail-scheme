//! A host entry for independently authored Wasm, without compiler services.

use native_runtime::native;
use std::sync::atomic::{AtomicBool, Ordering};

unsafe extern "C" {
    fn native_module_init();
    #[link_name = "wasm.run"]
    fn run(value: i64) -> i64;
    #[link_name = "wasm.previous"]
    fn previous() -> i64;
    #[link_name = "wasm-global.root"]
    fn root() -> u64;
    #[link_name = "wasm.take-root"]
    fn take_root() -> i64;
    #[link_name = "wasm.trap"]
    fn trap();
}

static RECLAIMED: AtomicBool = AtomicBool::new(false);

// The callback records reclamation without retaining its managed object.
unsafe extern "C" fn reclaimed(_: *mut std::ffi::c_void, _: *mut std::ffi::c_void) {
    RECLAIMED.store(true, Ordering::Relaxed);
}

fn check_import_roots() {
    unsafe {
        native::native_gc_watch(
            root() as *mut _,
            Some(reclaimed),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
        );
        let before = native::native_gc_collections();
        assert_eq!(take_root(), 3);
        assert!(native::native_gc_collections() > before);
        assert!(!RECLAIMED.load(Ordering::Relaxed));
        native::native_gc_collect();
        assert!(RECLAIMED.load(Ordering::Relaxed));
        assert!(native::native_roots.is_null());
    }
}

fn main() {
    native_runtime::native::initialize_host();
    unsafe { native_module_init() };
    if std::env::args().nth(1).as_deref() == Some("trap") {
        unsafe { trap() };
        std::process::exit(2);
    }
    assert_eq!(
        native::GC_STRESS,
        std::env::args().nth(1).as_deref() == Some("stress")
    );
    assert_eq!(unsafe { run(40) }, 42);
    assert_eq!(unsafe { run(1) }, 3);
    assert_eq!(unsafe { previous() }, 42);
    check_import_roots();
    if native::GC_STRESS {
        assert!(unsafe { native::gc_moved_objects() } > 0);
    }
    println!("42");
    std::process::exit(native_runtime::native::native_finish(0));
}
