//! The native worker checks the same result and resource lifetime as the V8 host.

include!("case-config.rs");

unsafe extern "C" {
    fn native_host_init(argc: i32, argv: *const *const u8);
    fn native_module_init();
    fn native_finish(status: i32) -> i32;
    fn native_resource_release_count() -> u64;
    fn benchmark_barriers() -> i64;
    fn benchmark_reset_barriers();
    #[link_name = "wasm.main"]
    fn guest_main();
    #[link_name = "wasm.bench"]
    fn guest_bench(count: i64) -> BenchResult;
}

// ---- Initialization, measured work and terminal resource ownership ----

fn matches_optional(expected: i64, observed: u64) -> bool {
    expected < 0 || expected as u64 == observed
}

fn main() {
    let status = unsafe { run() };
    std::process::exit(status);
}

unsafe fn run() -> i32 {
    unsafe {
        native_host_init(0, std::ptr::null());
        native_module_init();
        guest_main();
        let setup = benchmark_barriers();
        let setup_closed = native_resource_release_count();
        benchmark_reset_barriers();
        assert_configured_count();
        let result = guest_bench(CONFIGURED_COUNT);
        let worker_closed = native_resource_release_count() - setup_closed;
        let passed = result == EXPECTED_RESULT
            && (EXPECTED_SETUP < 0 || setup == EXPECTED_SETUP)
            && benchmark_barriers() == EXPECTED_BARRIERS
            && matches_optional(EXPECTED_SETUP_CLOSED, setup_closed)
            && matches_optional(EXPECTED_WORKER_CLOSED, worker_closed);
        let status = native_finish(i32::from(!passed));
        let cleanup_closed = native_resource_release_count() - setup_closed - worker_closed;
        println!(
            "{{\"result\":\"{result}\",\"barriers\":{},\"setup_closed\":{setup_closed},\"worker_closed\":{worker_closed},\"cleanup_closed\":{cleanup_closed}}}",
            benchmark_barriers()
        );
        if cleanup_closed == 0 { status } else { 1 }
    }
}
