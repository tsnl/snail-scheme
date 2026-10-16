unsafe extern "C" {
    fn native_host_init(argc: i32, argv: *const *const u8);
    fn native_module_init();
    fn native_finish(status: i32) -> i32;
    fn benchmark_barriers() -> i64;
    #[link_name = "wasm.main"]
    fn guest_main();
    #[link_name = "wasm.configured-count"]
    fn configured_count() -> i64;
    #[link_name = "wasm.observe"]
    fn observe() -> i64;
    #[link_name = "wasm.observe-fatal"]
    fn observe_fatal() -> i64;
    #[link_name = "wasm.bench"]
    fn bench(count: i64) -> i64;
    #[link_name = "snail:io/close-all"]
    fn close_all() -> i32;
}

// ---- Probes and the fatal handler execute inside the compiled program ----

fn main() {
    unsafe {
        native_host_init(0, std::ptr::null());
        native_module_init();
        guest_main();
        assert_eq!(configured_count(), 2000);
        if std::env::args().nth(1).as_deref() == Some("fatal") {
            observe_fatal();
            panic!("fatal compiler handler returned");
        }
        assert!(observe() == 22 && benchmark_barriers() == 0);
        println!("22");
        assert!(bench(2000) == 1 && benchmark_barriers() == 6000);
        assert_eq!(close_all(), 0);
        println!("canonical2000 passed");
        std::process::exit(native_finish(0));
    }
}
