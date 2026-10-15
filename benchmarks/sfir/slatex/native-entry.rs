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
    #[link_name = "wasm.bench"]
    fn bench(count: i64) -> i64;
}

// ---- Canonical worker and explicit resource lifetimes ----

fn main() {
    unsafe {
        native_host_init(0, std::ptr::null());
        native_module_init();
        guest_main();
        assert!(configured_count() == 500 && benchmark_barriers() == 0);
        assert_eq!(native_resource_release_count(), 1);
        assert!(bench(500) == 1 && benchmark_barriers() == 500);
        assert_eq!(native_resource_release_count(), 94502);
        let status = native_finish(0);
        assert_eq!(native_resource_release_count(), 94502);
        println!("canonical 500; setup closed 1; worker closed 94501; cleanup closed 0");
        std::process::exit(status);
    }
}
