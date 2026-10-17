#[path = "../native-support.rs"]
mod support;
unsafe extern "C" {
    #[link_name = "wasm.main"]
    fn lofi_main() -> i32;
    #[cfg(test_conversion)]
    #[link_name = "wasm.convert"]
    fn convert(value: f32) -> i32;
}

fn main() {
    let arguments = support::initialize();
    assert_eq!(unsafe { lofi_main() }, 42);
    #[cfg(test_conversion)]
    if arguments.len() == 3 {
        assert_eq!(
            unsafe { convert(support::number(&arguments[1]) as f32) },
            arguments[2].parse::<i32>().unwrap()
        );
        support::finish(0);
    }
    assert_eq!(arguments.len(), 1);
    support::finish(0);
}
