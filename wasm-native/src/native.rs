//! Native host services for mechanically lowered Wasm.
//!
//! The generated module and this runtime form one single-threaded instance per
//! process. Compiled code publishes exact reference roots before collecting
//! calls. Scalar resources never own managed roots or call guest code while
//! borrowed. The unsafe ABI accepts only validated compiler-generated layouts.

#[cfg(not(test))]
use crate::native_gc::Layout;
use crate::native_gc::{Collector, Config, Finalizer, Metadata};
use std::{
    ffi::{CStr, c_char, c_void},
    io::Write,
    ptr,
    sync::atomic::{AtomicU64, Ordering},
};

#[path = "native_worker.rs"]
pub mod worker;

// ---- Native ABI and owned runtime ----

#[repr(C)]
pub struct NativeRoots {
    pub previous: *mut NativeRoots,
    pub capacity: u64,
    pub count: u64,
    pub values: [u64; 0],
}

#[repr(C)]
pub struct NativeTable {
    pub values: *mut u64,
    pub length: u32,
    pub maximum: u32,
}

#[repr(C)]
struct NativeLayout {
    kind: u32,
    count: u32,
    offsets: *const u32,
}

#[cfg(not(test))]
unsafe extern "C" {
    static native_gc_layouts: NativeLayout;
    static native_gc_layouts_count: u64;
    static native_gc_globals: *const u64;
    static native_gc_globals_count: u64;
    static native_gc_tables: *const NativeTable;
    static native_gc_tables_count: u64;
    static native_gc_parents: u64;
    static native_gc_parents_count: u64;
}

struct Runtime {
    collector: Collector,
    parents: Vec<u64>,
    allocations: u64,
    collection_interval: u64,
}

// This pointer is installed once before guest code and never shared between
// threads. Finalizers may queue scalar IDs but cannot reenter this runtime.
static mut RUNTIME: *mut Runtime = ptr::null_mut();
#[unsafe(no_mangle)]
pub static mut native_roots: *mut NativeRoots = ptr::null_mut();
static mut ROOT_DEPTH: u64 = 0;
static mut PEAK_ROOT_DEPTH: u64 = 0;
static RELEASED_RESOURCES: AtomicU64 = AtomicU64::new(0);

unsafe fn runtime() -> &'static mut Runtime {
    if unsafe { RUNTIME.is_null() } {
        native_trap();
    }
    unsafe { &mut *RUNTIME }
}

unsafe fn foreign_slice<T>(pointer: *const T, count: u64) -> &'static [T] {
    if count == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(pointer, count as usize) }
    }
}

#[cfg(not(test))]
unsafe fn linked_metadata() -> (Metadata, Vec<u64>) {
    let layouts = unsafe { foreign_slice(&raw const native_gc_layouts, native_gc_layouts_count) }
        .iter()
        .map(|layout| match layout.kind {
            2 => Layout::ReferenceArray,
            0 | 1 => Layout::Fields(
                unsafe { foreign_slice(layout.offsets, layout.count as u64) }.to_vec(),
            ),
            _ => native_trap(),
        })
        .collect();
    let globals =
        unsafe { foreign_slice(&raw const native_gc_globals, native_gc_globals_count) }.to_vec();
    let tables =
        unsafe { foreign_slice(&raw const native_gc_tables, native_gc_tables_count) }.to_vec();
    let parents =
        unsafe { foreign_slice(&raw const native_gc_parents, native_gc_parents_count) }.to_vec();
    (
        Metadata {
            layouts,
            globals,
            tables,
        },
        parents,
    )
}

#[cfg(test)]
unsafe fn linked_metadata() -> (Metadata, Vec<u64>) {
    (Metadata::default(), Vec::new())
}

// ---- Traps and terminal cleanup ----

pub(crate) fn resource_released() {
    RELEASED_RESOURCES.fetch_add(1, Ordering::Relaxed);
}

#[unsafe(no_mangle)]
pub extern "C" fn native_resource_released() {
    resource_released();
}

#[unsafe(no_mangle)]
pub extern "C" fn native_resource_release_count() -> u64 {
    RELEASED_RESOURCES.load(Ordering::Relaxed)
}

#[unsafe(no_mangle)]
pub extern "C" fn snail_native_cleanup() -> i32 {
    // The registry is taken before any files are dropped. Repeated cleanup is
    // empty, and borrowed standard descriptors remain open.
    crate::strict_io::close_all()
}

#[unsafe(no_mangle)]
pub extern "C" fn native_finish(status: i32) -> i32 {
    if snail_native_cleanup() != 0 && status == 0 {
        1
    } else {
        status
    }
}

fn fail_bytes(prefix: &[u8], message: &[u8]) -> ! {
    {
        let mut error = std::io::stderr().lock();
        let _ = error.write_all(prefix);
        let _ = error.write_all(message);
        let _ = error.write_all(b"\n");
    }
    std::process::exit(native_finish(1));
}

pub(crate) fn report_error(message: &str) -> ! {
    fail_bytes(b"snail-sfir: ", message.as_bytes());
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn native_fail(message: *const c_char) -> ! {
    fail_bytes(b"", unsafe { CStr::from_ptr(message) }.to_bytes());
}

#[unsafe(no_mangle)]
pub extern "C" fn native_trap() -> ! {
    fail_bytes(b"", b"WebAssembly trap");
}

// Native pointers and sizes stay separate from the memory32 diagnostics import.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn native_report_error(bytes: *const u8, length: usize) -> ! {
    let message = unsafe { std::slice::from_raw_parts(bytes, length) };
    fail_bytes(b"snail-sfir: ", message);
}

// ---- Published roots and allocation ----

#[unsafe(no_mangle)]
pub extern "C" fn native_roots_reset_peak() {
    unsafe {
        PEAK_ROOT_DEPTH = ROOT_DEPTH;
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn native_roots_peak() -> u64 {
    unsafe { PEAK_ROOT_DEPTH }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn native_roots_enter(frame: *mut NativeRoots, capacity: u64) {
    unsafe {
        (*frame).capacity = capacity;
        (*frame).count = 0;
        if capacity == 0 {
            return;
        }
        (*frame).previous = native_roots;
        native_roots = frame;
        ROOT_DEPTH += 1;
        PEAK_ROOT_DEPTH = PEAK_ROOT_DEPTH.max(ROOT_DEPTH);
    }
}

// Tail transfers unlink before entering their callee. There is no asynchronous
// collection: each collecting call observes the whole live translated stack.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn native_roots_leave(frame: *mut NativeRoots) {
    unsafe {
        if (*frame).capacity != 0 {
            native_roots = (*frame).previous;
            ROOT_DEPTH -= 1;
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn native_gc_alloc(bytes: usize) -> *mut c_void {
    unsafe { runtime().collector.allocate(bytes, native_roots).cast() }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn native_gc_collect() {
    unsafe { runtime().collector.collect(native_roots) };
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn native_gc_collections() -> usize {
    unsafe { runtime().collector.collections() }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn native_gc_watch(
    object: *mut c_void,
    callback: Option<Finalizer>,
    data: *mut c_void,
    old_callback: *mut Option<Finalizer>,
    old_data: *mut *mut c_void,
) {
    let (callback, data) = unsafe { runtime().collector.watch(object, callback, data) };
    unsafe {
        if !old_callback.is_null() {
            old_callback.write(callback);
        }
        if !old_data.is_null() {
            old_data.write(data);
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn native_alloc(size: u64) -> u64 {
    let state = unsafe { runtime() };
    if state.collection_interval != 0 {
        state.allocations += 1;
        if state.allocations % state.collection_interval == 0 {
            unsafe { state.collector.collect(native_roots) };
        }
    }
    let object = unsafe { state.collector.allocate(size as usize, native_roots) };
    if object.is_null() {
        fail_bytes(b"", b"native GC arena exhausted (SNAIL_GC_HEAP_BYTES)");
    }
    object as u64
}

fn object_words(reference: u64) -> *mut u64 {
    if reference == 0 || reference & 1 != 0 {
        native_trap();
    }
    reference as *mut u64
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn native_ref_test(
    reference: u64,
    kind: i64,
    nullable: u32,
    exact: u32,
) -> u32 {
    if reference == 0 {
        return nullable;
    }
    if kind == -1 {
        return u32::from(reference & 1 != 0 || unsafe { *object_words(reference) } & 3 != 0);
    }
    if kind == -2 {
        return (reference & 1) as u32;
    }
    if reference & 1 != 0 || kind == -6 {
        return 0;
    }
    let mut actual = unsafe { *object_words(reference) };
    if kind < 0 {
        return u32::from(
            actual & 3
                == match kind {
                    -3 => 2,
                    -4 => 3,
                    _ => 0,
                },
        );
    }
    let parents = &unsafe { runtime() }.parents;
    while actual != kind as u64 && exact == 0 && actual != 0 {
        let index = (actual >> 2).wrapping_sub(1) as usize;
        actual = *parents.get(index).unwrap_or_else(|| native_trap());
    }
    u32::from(actual == kind as u64)
}

// ---- Packed arrays and rooted tables ----

// Arrays have two eight-byte header words, followed by tightly packed Wasm
// elements. LLVM supplies the validated stride; references always use eight.
unsafe fn array_fill(payload: *mut u8, length: u32, initial: u64, stride: u32) {
    match stride {
        1 => unsafe { ptr::write_bytes(payload, initial as u8, length as usize) },
        2 => {
            for index in 0..length as usize {
                unsafe { payload.cast::<u16>().add(index).write(initial as u16) };
            }
        }
        4 => {
            for index in 0..length as usize {
                unsafe { payload.cast::<u32>().add(index).write(initial as u32) };
            }
        }
        8 => {
            for index in 0..length as usize {
                unsafe { payload.cast::<u64>().add(index).write(initial) };
            }
        }
        _ => native_trap(),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn native_array_new(
    kind: u64,
    length: u32,
    initial: u64,
    stride: u32,
) -> u64 {
    let reference = unsafe { native_alloc(16 + length as u64 * stride as u64) };
    let words = object_words(reference);
    unsafe {
        words.write(kind);
        words.add(1).write(length as u64);
        array_fill(words.add(2).cast(), length, initial, stride);
    }
    reference
}

// Kept for previously emitted native objects. Current LLVM lowering performs
// the same checked header/address operations directly; allocation stays here.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn native_array_length(reference: u64) -> u32 {
    unsafe { *object_words(reference).add(1) as u32 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn native_array_slot(reference: u64, index: u32, stride: u32) -> *mut c_void {
    let words = object_words(reference);
    if index as u64 >= unsafe { *words.add(1) } {
        native_trap();
    }
    unsafe {
        words
            .add(2)
            .cast::<u8>()
            .add(index as usize * stride as usize)
            .cast()
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn native_array_copy(
    target: u64,
    to: u32,
    source: u64,
    from: u32,
    count: u32,
    stride: u32,
) {
    let (destination, origin) = (object_words(target), object_words(source));
    if to as u64 + count as u64 > unsafe { *destination.add(1) }
        || from as u64 + count as u64 > unsafe { *origin.add(1) }
    {
        native_trap();
    }
    unsafe {
        ptr::copy(
            origin
                .add(2)
                .cast::<u8>()
                .add(from as usize * stride as usize),
            destination
                .add(2)
                .cast::<u8>()
                .add(to as usize * stride as usize),
            count as usize * stride as usize,
        );
    }
}

fn table_allocate(length: u32) -> *mut u64 {
    // Table buffers have explicit ownership outside managed regions. The
    // permanent table identity lets the collector see the current cells.
    unsafe { libc::calloc((length as usize).max(1), 8).cast() }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn native_table_init(table: *mut NativeTable, length: u32, maximum: u32) {
    if length > maximum {
        native_trap();
    }
    let values = table_allocate(length);
    if values.is_null() {
        native_trap();
    }
    unsafe {
        table.write(NativeTable {
            values,
            length,
            maximum,
        });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn native_table_check(table: *const NativeTable, offset: u32, count: u32) {
    // Empty active element segments still validate their offset.
    if offset as u64 + count as u64 > unsafe { (*table).length } as u64 {
        native_trap();
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn native_table_slot(table: *mut NativeTable, index: u32) -> *mut c_void {
    unsafe {
        native_table_check(table, index, 1);
        (*table).values.add(index as usize).cast()
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn native_table_size(table: *const NativeTable) -> u32 {
    unsafe { (*table).length }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn native_table_grow(
    table: *mut NativeTable,
    initial: u64,
    delta: u32,
) -> u32 {
    let table = unsafe { &mut *table };
    let old = table.length;
    if delta == 0 {
        return old;
    }
    if old as u64 + delta as u64 > table.maximum as u64 {
        return u32::MAX;
    }
    let values = table_allocate(old + delta);
    if values.is_null() {
        return u32::MAX;
    }
    unsafe {
        ptr::copy_nonoverlapping(table.values, values, old as usize);
    }
    for index in old..old + delta {
        unsafe { values.add(index as usize).write(initial) };
    }
    unsafe { libc::free(table.values.cast()) };
    table.values = values;
    table.length = old + delta;
    old
}

// ---- Defined numeric boundaries ----

// Wasm traps where LLVM division and float-to-integer conversion are undefined.
macro_rules! signed_division {
    ($type:ty, $divide:ident, $remainder:ident) => {
        #[unsafe(no_mangle)]
        pub extern "C" fn $divide(a: $type, b: $type) -> $type {
            a.checked_div(b).unwrap_or_else(|| native_trap())
        }
        #[unsafe(no_mangle)]
        pub extern "C" fn $remainder(a: $type, b: $type) -> $type {
            if b == 0 {
                native_trap();
            }
            a.wrapping_rem(b)
        }
    };
}
signed_division!(i32, native_i32_div_s, native_i32_rem_s);
signed_division!(i64, native_i64_div_s, native_i64_rem_s);

macro_rules! truncation {
    ($name:ident, $source:ty, $target:ty, $lower:expr, $upper:expr) => {
        #[unsafe(no_mangle)]
        pub extern "C" fn $name(value: $source) -> $target {
            let value = (value as f64).trunc();
            if !(value >= $lower && value < $upper) {
                native_trap();
            }
            value as $target
        }
    };
}
truncation!(
    native_i32_trunc_f32_s,
    f32,
    i32,
    -2147483648.0,
    2147483648.0
);
truncation!(native_i32_trunc_f32_u, f32, u32, 0.0, 4294967296.0);
truncation!(
    native_i32_trunc_f64_s,
    f64,
    i32,
    -2147483648.0,
    2147483648.0
);
truncation!(native_i32_trunc_f64_u, f64, u32, 0.0, 4294967296.0);
truncation!(
    native_i64_trunc_f32_s,
    f32,
    i64,
    -9223372036854775808.0,
    9223372036854775808.0
);
truncation!(
    native_i64_trunc_f32_u,
    f32,
    u64,
    0.0,
    18446744073709551616.0
);
truncation!(
    native_i64_trunc_f64_s,
    f64,
    i64,
    -9223372036854775808.0,
    9223372036854775808.0
);
truncation!(
    native_i64_trunc_f64_u,
    f64,
    u64,
    0.0,
    18446744073709551616.0
);

// ---- Process initialization ----

extern "C" fn report_statistics() {
    if !unsafe { RUNTIME.is_null() } {
        unsafe { runtime().collector.report_statistics() };
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn native_gc_init() {
    if !unsafe { RUNTIME.is_null() } {
        native_trap();
    }
    let (metadata, parents) = unsafe { linked_metadata() };
    let collector =
        Collector::new(Config::from_environment(), metadata).unwrap_or_else(|| native_trap());
    let collection_interval = std::env::var("SNAIL_NATIVE_GC_INTERVAL")
        .ok()
        .and_then(|text| text.parse().ok())
        .unwrap_or(0);
    let state = Runtime {
        collector,
        parents,
        allocations: 0,
        collection_interval,
    };
    unsafe {
        RUNTIME = Box::into_raw(Box::new(state));
        libc::atexit(report_statistics);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn native_host_init(_argc: i32, _argv: *mut *mut c_char) {
    unsafe { native_gc_init() };
}

pub fn initialize_host() {
    unsafe { native_host_init(0, ptr::null_mut()) };
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn integer_boundaries_match_wasm_remainders() {
        assert_eq!(native_i32_div_s(-11, 2), -5);
        assert_eq!(native_i64_div_s(11, -2), -5);
        assert_eq!(native_i32_rem_s(i32::MIN, -1), 0);
        assert_eq!(native_i64_rem_s(i64::MIN, -1), 0);
        assert_eq!(native_i32_trunc_f64_s(-2147483648.75), i32::MIN);
        assert_eq!(native_i64_trunc_f64_u(-0.75), 0);
        assert_eq!(native_i32_trunc_f32_u(42.75), 42);
    }

    #[test]
    fn packed_fill_retains_low_bits_and_copy_handles_overlap() {
        let initial = 0xfedc_ba98_7654_3210;
        for stride in [1, 2, 4, 8] {
            let mut words = [6_u64, 4, 0, 0, 0, 0];
            unsafe { array_fill(words.as_mut_ptr().add(2).cast(), 4, initial, stride) };
            let bytes = unsafe {
                std::slice::from_raw_parts(words.as_ptr().add(2).cast::<u8>(), 4 * stride as usize)
            };
            for value in bytes.chunks_exact(stride as usize) {
                assert_eq!(value, &initial.to_ne_bytes()[..stride as usize]);
            }
            let reference = words.as_mut_ptr() as u64;
            unsafe { native_array_copy(reference, 1, reference, 0, 3, stride) };
        }
    }

    #[test]
    fn table_growth_retains_values_and_respects_maximum() {
        let mut table = NativeTable {
            values: ptr::null_mut(),
            length: 0,
            maximum: 0,
        };
        unsafe {
            native_table_init(&mut table, 2, 4);
            *table.values = 12;
            assert_eq!(native_table_grow(&mut table, 99, 0), 2);
            assert_eq!(native_table_grow(&mut table, 99, 2), 2);
            assert_eq!(
                std::slice::from_raw_parts(table.values, 4),
                &[12, 0, 99, 99]
            );
            assert_eq!(native_table_grow(&mut table, 88, 1), u32::MAX);
            assert_eq!(table.length, 4);
            libc::free(table.values.cast());
        }
    }
}
