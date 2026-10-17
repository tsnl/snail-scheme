unsafe extern "C" {
    fn native_host_init(argc: i32, argv: *const *const u8);
    fn native_module_init();
    fn native_finish(status: i32) -> i32;
    fn benchmark_load_input(path: *const u8, length: usize) -> i64;
    fn barrier_count() -> u64;
    #[link_name = "wasm.main"]
    fn guest_main();
    #[link_name = "wasm.bench"]
    fn bench(count: i64) -> i64;
    #[link_name = "wasm.observe"]
    fn observe();
}

// ---- Full canonical count and complete observed decimal result ----

fn main() {
    let arguments: Vec<String> = std::env::args().collect();
    assert_eq!(arguments.len(), 2);
    unsafe {
        native_host_init(0, std::ptr::null());
        native_module_init();
        let count = benchmark_load_input(arguments[1].as_ptr(), arguments[1].len());
        guest_main();
        assert!(bench(count) == 1 && barrier_count() == 3 * count as u64);
        observe();
        std::process::exit(native_finish(0));
    }
}
