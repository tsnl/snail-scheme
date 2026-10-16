//! A host entry for independently authored Wasm, without compiler services.

unsafe extern "C" {
    fn native_module_init();
    #[link_name = "wasm.run"]
    fn run(value: i64) -> i64;
    #[link_name = "wasm.previous"]
    fn previous() -> i64;
    #[link_name = "wasm.trap"]
    fn trap();
}

fn main() {
    snail_runtime::native::initialize_host();
    unsafe { native_module_init() };
    if std::env::args().nth(1).as_deref() == Some("trap") {
        unsafe { trap() };
        std::process::exit(2);
    }
    assert_eq!(unsafe { run(40) }, 42);
    assert_eq!(unsafe { run(1) }, 3);
    assert_eq!(unsafe { previous() }, 42);
    println!("42");
    std::process::exit(snail_runtime::native::native_finish(0));
}
