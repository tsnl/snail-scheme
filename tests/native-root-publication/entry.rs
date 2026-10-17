use native_runtime::native;
use std::sync::atomic::{AtomicU64, Ordering};

unsafe extern "C" {
    fn native_module_init();
    #[link_name = "wasm.run"]
    fn run(condition: i32) -> i64;
    #[link_name = "wasm.arrays"]
    fn arrays() -> i64;
}

// ---- Imported collection rewrites published caller roots ----

static COLLECTS: AtomicU64 = AtomicU64::new(0);
static PAIRS: AtomicU64 = AtomicU64::new(0);
static ROOT_CHECKS: AtomicU64 = AtomicU64::new(0);

fn check_roots(expected: &[i64]) -> [u64; 3] {
    let mut addresses = [0; 3];
    unsafe {
        let frame = native::native_roots;
        assert!(!frame.is_null());
        assert_eq!((*frame).count as usize, expected.len());
        assert!((*frame).count <= (*frame).capacity);
        let values = (&raw const (*frame).values).cast::<u64>();
        let mut actual = [0_i64; 3];
        for index in 0..expected.len() {
            addresses[index] = values.add(index).read();
            assert_ne!(addresses[index], 0);
            actual[index] = (addresses[index] as *const i64).add(1).read();
        }
        actual[..expected.len()].sort_unstable();
        assert_eq!(&actual[..expected.len()], expected);
    }
    ROOT_CHECKS.fetch_add(1, Ordering::Relaxed);
    addresses
}

fn collect_roots(expected: &[i64]) {
    let before = check_roots(expected);
    unsafe { native::native_gc_collect() };
    let after = check_roots(expected);
    if native::GC_STRESS {
        assert_ne!(before, after);
    }
}

#[unsafe(export_name = "root_publication_collect")]
pub extern "C" fn collect() -> i32 {
    COLLECTS.fetch_add(1, Ordering::Relaxed);
    collect_roots(&[11, 22, 33]);
    0
}

// Root writes preserve the same objects at their relocated addresses. Arbitrary
// clobbering would destroy the authoritative references before restoration.
#[unsafe(export_name = "root_publication_collect_two")]
pub extern "C" fn collect_two() {
    PAIRS.fetch_add(1, Ordering::Relaxed);
    collect_roots(&[11, 22]);
}

// ---- Operand aliases, both branches, loop backedges and tail transfer ----

fn main() {
    native::initialize_host();
    unsafe {
        native_module_init();
        assert_eq!(run(0), 66);
        assert_eq!(run(1), 66);
        assert_eq!(arrays(), 42);
        assert!(native::native_roots.is_null());
        if native::GC_STRESS {
            assert!(native::gc_moved_objects() > 0);
        }
    }
    assert_eq!(COLLECTS.load(Ordering::Relaxed), 12);
    assert_eq!(PAIRS.load(Ordering::Relaxed), 2);
    assert_eq!(ROOT_CHECKS.load(Ordering::Relaxed), 28);
    std::process::exit(native::native_finish(0));
}
