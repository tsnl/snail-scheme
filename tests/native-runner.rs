#[path = "native-support.rs"]
mod support;
unsafe extern "C" {
    #[link_name = "wasm.left"]
    fn left(p0: i64) -> u64;
    #[link_name = "wasm.read-parent"]
    fn read_parent(p0: u64) -> i64;
    #[link_name = "wasm.read-right"]
    fn read_right(p0: u64) -> i64;
    #[link_name = "wasm.same-left"]
    fn same_left(p0: u64) -> u32;
    #[link_name = "wasm.is-right"]
    fn is_right(p0: u64) -> u32;
    #[link_name = "wasm.cyclic"]
    fn cyclic(p0: u64) -> u32;
    #[link_name = "wasm.check"]
    fn check() -> u32;
    #[link_name = "wasm.tail"]
    fn tail(p0: u32) -> u64;
    #[link_name = "wasm.root"]
    fn root(p0: u32) -> u64;
    #[link_name = "wasm.gc-effects"]
    fn gc_effects() -> u64;
    #[link_name = "wasm.tail-gc"]
    fn tail_gc(p0: u32) -> u64;
    #[link_name = "wasm.gc-operands"]
    fn gc_operands() -> u64;
    #[link_name = "wasm.gc-control"]
    fn gc_control(condition: u32) -> u64;
    #[link_name = "wasm.trap"]
    fn trap(p0: u32);
    #[link_name = "wasm.i31-s"]
    fn i31_signed(p0: i32) -> i32;
    #[link_name = "wasm.i31-u"]
    fn i31_unsigned(p0: i32) -> u32;
    #[link_name = "wasm.i31-eq-negative"]
    fn i31_equal_negative(p0: i32) -> u32;
    #[link_name = "wasm.sat-i32-f32-s"]
    fn sat_i32_f32_s(p0: f32) -> u32;
    #[link_name = "wasm.sat-i32-f32-u"]
    fn sat_i32_f32_u(p0: f32) -> u32;
    #[link_name = "wasm.sat-i32-f64-s"]
    fn sat_i32_f64_s(p0: f64) -> u32;
    #[link_name = "wasm.sat-i32-f64-u"]
    fn sat_i32_f64_u(p0: f64) -> u32;
    #[link_name = "wasm.sat-i64-f32-s"]
    fn sat_i64_f32_s(p0: f32) -> u64;
    #[link_name = "wasm.sat-i64-f32-u"]
    fn sat_i64_f32_u(p0: f32) -> u64;
    #[link_name = "wasm.sat-i64-f64-s"]
    fn sat_i64_f64_s(p0: f64) -> u64;
    #[link_name = "wasm.sat-i64-f64-u"]
    fn sat_i64_f64_u(p0: f64) -> u64;
    #[link_name = "wasm.storage-check"]
    fn storage_check(p0: u32) -> u32;
    #[link_name = "wasm.storage-trap"]
    fn storage_trap(p0: u32);
    #[link_name = "wasm.storage-u8"]
    fn storage_u8(p0: u32, p1: u32) -> u64;
    #[link_name = "wasm.storage-u16"]
    fn storage_u16(p0: u32, p1: u32) -> u64;
    #[link_name = "wasm.storage-i32"]
    fn storage_i32(p0: u32, p1: u32) -> u64;
    #[link_name = "wasm.storage-f32"]
    fn storage_f32(p0: u32, p1: u32) -> u64;
    #[link_name = "wasm.storage-f64"]
    fn storage_f64(p0: u32, p1: u64) -> u64;
    #[link_name = "wasm.storage-refs"]
    fn storage_refs(p0: u32) -> u64;
    #[link_name = "wasm.storage-static-u8"]
    fn static_u8() -> u64;
    #[link_name = "wasm.storage-static-u16"]
    fn static_u16() -> u64;
    #[link_name = "wasm.storage-static-i32"]
    fn static_i32() -> u64;
    #[link_name = "wasm.storage-static-f32"]
    fn static_f32() -> u64;
    #[link_name = "wasm.storage-static-f64"]
    fn static_f64() -> u64;
    #[link_name = "wasm.storage-global-f32-bits"]
    fn global_f32_bits() -> u64;
    #[link_name = "wasm.storage-identity"]
    fn storage_identity() -> u32;
    #[link_name = "wasm.storage-roots"]
    fn storage_roots() -> u64;
    #[link_name = "wasm.storage-access"]
    fn storage_access(reference: u64, index: u32, operation: u32) -> u32;
    #[link_name = "wasm.storage-order"]
    fn storage_order() -> u32;
}

use snail_runtime::native::{self, NativeRoots};
use std::sync::atomic::{AtomicU32, Ordering};

// ---- Inspect returned references only across nonallocating host operations ----

unsafe fn check_payload<T: Copy + PartialEq + std::fmt::Debug>(reference: u64, expected: &[T]) {
    let words = reference as *const u64;
    assert_eq!(unsafe { *words.add(1) }, expected.len() as u64);
    let actual = unsafe { std::slice::from_raw_parts(words.add(2).cast::<T>(), expected.len()) };
    assert_eq!(actual, expected);
}

unsafe fn check_array_storage() {
    unsafe {
        check_payload(storage_u8(3, 0x12345), &[0x45u8; 3]);
        check_payload(storage_u16(3, 0x12345), &[0x2345u16; 3]);
        check_payload(storage_i32(3, 0x12345), &[0x12345u32; 3]);
        check_payload(storage_f32(3, 0x80000000), &[0x80000000u32; 3]);
        check_payload(
            storage_f64(2, 0x8000000000000000),
            &[0x8000000000000000u64; 2],
        );
        check_payload(storage_f32(2, 0x7fc12345), &[0x7fc12345u32; 2]);
        check_payload(
            storage_f64(2, 0x7ff8000000001234),
            &[0x7ff8000000001234u64; 2],
        );
        // Forced collection reclaims the preceding nonzero arrays. Defaults
        // must still expose cleared scalar payloads and null reference edges.
        check_payload(storage_u8(3, 0), &[0u8; 3]);
        check_payload(storage_u16(3, 0), &[0u16; 3]);
        check_payload(storage_i32(3, 0), &[0u32; 3]);
        check_payload(storage_f32(3, 0), &[0u32; 3]);
        check_payload(storage_f64(3, 0), &[0u64; 3]);
        check_payload(storage_refs(3), &[0u64; 3]);
        check_payload(storage_u8(0, 42), &[] as &[u8]);
        check_payload(static_u8(), &[255u8, 52, 128]);
        check_payload(static_u16(), &[65535u16, 9029, 32768]);
        check_payload(static_i32(), &[u32::MAX, 42, i32::MAX as u32]);
        check_payload(static_f32(), &[0u32; 3]);
        check_payload(
            static_f64(),
            &[
                0x8000000000000000u64,
                0x3ff8000000000000,
                0x7ff8000000001234,
            ],
        );
        check_payload(global_f32_bits(), &[0x80000000u32, 0x7fc12345]);
        assert_eq!(
            (storage_identity(), storage_roots(), storage_check(0x12345)),
            (1, 77, 1)
        );
        let array = storage_u8(3, 0x45);
        assert_eq!(storage_access(array, 0, 0), 3);
        assert_eq!(storage_access(array, 2, 1), 0x45);
        assert_eq!(storage_access(array, 1, 2), 42);
        assert_eq!(storage_access(array, 1, 1), 42);
        assert_eq!(storage_access(storage_u8(0, 0), 0, 0), 0);
        // Probe every length result bit through the native ABI without a
        // multi-gigabyte allocation. This header permits no payload access.
        let header = [0_u64, u32::MAX as u64];
        assert_eq!(storage_access(header.as_ptr() as u64, 0, 0), u32::MAX);
    }
}

// ---- Operand side effects survive the native trap exit ----

static EXPECTED_STORAGE_ORDER: AtomicU32 = AtomicU32::new(0);

extern "C" fn check_storage_order() {
    assert_eq!(
        unsafe { storage_order() },
        EXPECTED_STORAGE_ORDER.load(Ordering::Relaxed)
    );
}

unsafe fn trap_array_access(reference: &str, operation: u32) {
    unsafe extern "C" {
        fn atexit(callback: extern "C" fn()) -> i32;
    }
    EXPECTED_STORAGE_ORDER.store(operation, Ordering::Relaxed);
    assert_eq!(unsafe { atexit(check_storage_order) }, 0);
    let (reference, index) = match reference {
        "null" => (0, 0),
        "i31" => (3, 0),
        "empty" => (unsafe { storage_u8(0, 0) }, 0),
        "upper" => (unsafe { storage_u8(3, 0) }, 0x8000_0000),
        _ => panic!("unknown array reference probe"),
    };
    unsafe { storage_access(reference, index, operation) };
}

unsafe fn saturation(input: &str) {
    let number = support::number(input);
    let narrow = number as f32;
    unsafe {
        println!(
            "{} {} {} {} {} {} {} {}",
            sat_i32_f32_s(narrow),
            sat_i32_f32_u(narrow),
            sat_i32_f64_s(number),
            sat_i32_f64_u(number),
            sat_i64_f32_s(narrow),
            sat_i64_f32_u(narrow),
            sat_i64_f64_s(number),
            sat_i64_f64_u(number)
        );
    }
}

// ---- Published roots survive collection and bounded tail calls reuse slots ----

unsafe fn check_roots() {
    unsafe {
        native::native_roots_reset_peak();
        assert_eq!(
            tail(if std::env::var_os("SNAIL_NATIVE_TAIL_STRESS").is_some() {
                2000
            } else {
                2_000_000
            }),
            42
        );
        assert!(native::native_roots_peak() < 8);
        assert_eq!(root(500), 99);
        assert_eq!(gc_effects(), 42);
        native::native_roots_reset_peak();
        assert_eq!(tail_gc(20_000), 42);
        assert!(native::native_roots_peak() < 8);
        assert_eq!(gc_operands(), 42);
        assert_eq!(gc_control(0), 42);
        assert_eq!(gc_control(1), 42);
        #[repr(C)]
        struct RootStorage {
            header: NativeRoots,
            values: [u64; 1],
        }
        let mut keep = RootStorage {
            header: NativeRoots {
                previous: std::ptr::null_mut(),
                capacity: 0,
                count: 0,
                values: [],
            },
            values: [0],
        };
        native::native_roots_enter(&mut keep.header, 1);
        keep.values[0] = left(i64::MIN);
        keep.header.count = 1;
        native::native_gc_collect();
        assert_eq!(read_parent(keep.values[0]), i64::MIN);
        assert_ne!(same_left(keep.values[0]), 0);
        assert_eq!(is_right(keep.values[0]), 0);
        assert_ne!(cyclic(keep.values[0]), 0);
        native::native_roots_leave(&mut keep.header);
        assert!(native::native_roots.is_null());
        assert!(native::native_gc_collections() > 1);
    }
}

fn main() {
    #[repr(C)]
    struct Limit {
        current: u64,
        maximum: u64,
    }
    unsafe extern "C" {
        fn setrlimit(resource: i32, limit: *const Limit) -> i32;
    }
    assert_eq!(
        unsafe {
            setrlimit(
                3,
                &Limit {
                    current: 256 * 1024,
                    maximum: 256 * 1024,
                },
            )
        },
        0
    );
    let arguments = support::initialize();
    unsafe {
        match arguments.get(1).map(String::as_str) {
            Some("saturate") => {
                saturation(&arguments[2]);
                support::finish(0);
            }
            Some("storage-trap") => {
                storage_trap(arguments[2].parse().unwrap());
                support::finish(2);
            }
            Some("storage-access-trap") => {
                trap_array_access(&arguments[2], arguments[3].parse().unwrap());
                support::finish(2);
            }
            Some("subtype-trap") => {
                read_right(left(41));
                support::finish(2);
            }
            Some(kind) => {
                trap(kind.parse().unwrap());
                support::finish(2);
            }
            None => {}
        }
        assert_eq!(check(), 0);
        check_array_storage();
        assert_eq!(
            (i31_signed(i32::MIN), i31_signed(1073741824), i31_signed(-1)),
            (0, -1073741824, -1)
        );
        assert_eq!(
            (
                i31_unsigned(-1),
                i31_signed(1073741823),
                i31_unsigned(1073741824),
                i31_signed(i32::MAX)
            ),
            (2147483647, 1073741823, 1073741824, -1)
        );
        assert_ne!(i31_equal_negative(-1), 0);
        assert_ne!(i31_equal_negative(i32::MAX), 0);
        assert_eq!(i31_equal_negative(0), 0);
        check_roots();
    }
    support::finish(0);
}
