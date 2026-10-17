//! Setup, formatting and cleanup stay outside the guest workload clock.

use std::time::Instant;

include!("case-config.rs");

unsafe extern "C" {
    fn native_host_init(argc: i32, argv: *const *const u8);
    fn native_module_init();
    fn native_finish(status: i32) -> i32;
    #[link_name = "wasm.main"]
    fn guest_main();
    #[link_name = "wasm.bench"]
    fn guest_bench(count: i64) -> BenchResult;
}

// ---- Work and its complete final predicate share one clock interval ----

fn main() {
    let status = unsafe { run() };
    std::process::exit(status);
}

unsafe fn run() -> i32 {
    unsafe {
        native_host_init(0, std::ptr::null());
        native_module_init();
        guest_main();
        assert_configured_count();
        let start = Instant::now();
        let result = guest_bench(CONFIGURED_COUNT);
        let passed = result == EXPECTED_RESULT;
        let seconds = start.elapsed().as_secs_f64();
        if !passed {
            return native_finish(1);
        }
        println!("{{\"result\":\"{result}\",\"seconds\":{seconds:.9}}}");
        native_finish(0)
    }
}
