#[path = "native-support.rs"]
mod support;

unsafe extern "C" {
    #[link_name = "wasm.main"]
    fn guest_main();
}

fn main() {
    support::observe_releases();
    support::initialize();
    unsafe { guest_main() };
    support::finish(0);
}
