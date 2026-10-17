use std::time::Instant;

unsafe extern "C" {
    fn native_host_init(argc: i32, argv: *const *const u8);
    fn native_module_init();
    fn native_finish(status: i32) -> i32;
    fn benchmark_load_input(path: *const u8, length: usize) -> i64;
    #[link_name = "wasm.main"]
    fn guest_main();
    #[link_name = "wasm.bench"]
    fn bench(count: i64) -> i64;
    #[link_name = "wasm.observe"]
    fn observe();
}

// ---- The complete decimal predicate precedes the ending clock ----

fn main() {
    let arguments: Vec<String> = std::env::args().collect();
    assert_eq!(arguments.len(), 2);
    unsafe {
        native_host_init(0, std::ptr::null());
        native_module_init();
        let count = benchmark_load_input(arguments[1].as_ptr(), arguments[1].len());
        guest_main();
        let start = Instant::now();
        let passed = bench(count) == 1;
        let seconds = start.elapsed().as_secs_f64();
        if !passed {
            std::process::exit(native_finish(1));
        }
        observe();
        println!("{{\"result\":\"1\",\"seconds\":{seconds:.9}}}");
        std::process::exit(native_finish(0));
    }
}
