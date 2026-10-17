// The build script selects a () -> I32 export. Its Wasm initializer and entry
// keep their physical signatures when the separate backend lowers them.
unsafe extern "C" {
    fn native_module_init();
    #[link_name = "wasm.main"]
    fn initialize();
    #[link_name = "wasm.entry"]
    fn answer() -> i32;
}

fn main() {
    native_runtime::native::initialize_host();
    unsafe {
        native_module_init();
        initialize();
        println!("{}", answer());
    }
    std::process::exit(native_runtime::native::native_finish(0));
}
