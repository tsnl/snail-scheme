unsafe extern "C" {
    fn native_host_init(argc: i32, argv: *const *const u8);
    fn native_module_init();
    fn native_finish(status: i32) -> i32;
    fn native_resource_release_count() -> u64;
    fn benchmark_barriers() -> i64;
    #[link_name = "wasm.main"]
    fn guest_main();
    #[link_name = "wasm.configured-count"]
    fn configured_count() -> i64;
    #[link_name = "wasm.observe"]
    fn observe() -> i64;
    #[link_name = "wasm.bench"]
    fn bench(count: i64) -> i64;
}

// ---- Complete interpreter probes precede the canonical sorting worker ----

fn main() {
    unsafe {
        native_host_init(0, std::ptr::null());
        native_module_init();
        guest_main();
        let setup_closed = native_resource_release_count();
        let mut passed =
            configured_count() == 100000 && benchmark_barriers() == 0 && setup_closed == 1;
        let probes = if passed { observe() } else { -1 };
        let probes_closed = native_resource_release_count() - setup_closed;
        passed &= probes == 26 && benchmark_barriers() == 0 && probes_closed == 1;
        let result = if passed { bench(100000) } else { -1 };
        let worker_closed = native_resource_release_count() - setup_closed - probes_closed;
        passed &= result == 1 && benchmark_barriers() == 100000 && worker_closed == 0;
        let status = native_finish(i32::from(!passed));
        let cleanup_closed =
            native_resource_release_count() - setup_closed - probes_closed - worker_closed;
        println!(
            "{{\"probes\":{probes},\"result\":{result},\"barriers\":{},\"setup_closed\":{setup_closed},\"probes_closed\":{probes_closed},\"worker_closed\":{worker_closed},\"cleanup_closed\":{cleanup_closed}}}",
            benchmark_barriers()
        );
        std::process::exit(if cleanup_closed == 0 { status } else { 1 });
    }
}
