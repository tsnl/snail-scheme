//! Instrumented GC diagnostics use the same workload and final predicate.
//! Build with native-runtime/gc-trace; pass the output trace path explicitly.

use native_runtime::native;

include!("case-config.rs");

unsafe extern "C" {
    fn native_module_init();
    #[link_name = "wasm.main"]
    fn guest_main();
    #[link_name = "wasm.bench"]
    fn guest_bench(count: i64) -> BenchResult;
}

// ---- Setup and trace serialization stay outside the collection recording ----

fn main() {
    assert!(
        !native::GC_STRESS,
        "pause diagnostics require production GC policy"
    );
    let path = std::env::args_os()
        .nth(1)
        .expect("expected trace output path");
    native::initialize_host();
    let (result, trace) = unsafe { run() };
    trace
        .write_chromium_json(std::fs::File::create(path).unwrap())
        .unwrap();
    let summary = trace.summary();
    println!(
        "{{\"result\":\"{result}\",\"collections\":{},\"dropped_events\":{},\"total_pause_us\":{},\"maximum_pause_us\":{}}}",
        summary.collections,
        summary.dropped_events,
        summary.total_pause.as_micros(),
        summary.maximum_pause.as_micros()
    );
    std::process::exit(native::native_finish(i32::from(result != EXPECTED_RESULT)));
}

unsafe fn run() -> (BenchResult, native::GcTrace) {
    unsafe {
        native_module_init();
        guest_main();
        assert_configured_count();
        native::gc_trace_start(16384).unwrap();
        let result = guest_bench(CONFIGURED_COUNT);
        let trace = native::gc_trace_take().unwrap();
        (result, trace)
    }
}
