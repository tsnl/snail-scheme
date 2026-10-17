#[path = "../native-support.rs"]
mod support;
unsafe extern "C" {
    #[link_name = "wasm.main"]
    fn lofi_main() -> i32;
    #[link_name = "wasm.effect-count"]
    fn effect_count() -> i32;
    #[link_name = "wasm.narrow-integer"]
    fn narrow_integer(p0: i32, p1: i64) -> i32;
    #[link_name = "wasm.narrow-float"]
    fn narrow_float(p0: i32, p1: f64) -> f32;
    #[link_name = "wasm.narrow-control"]
    fn narrow_control(p0: i32, p1: i32) -> i32;
}

// ---- Callers supply independently recorded integer and IEEE expectations ----

fn main() {
    let arguments = support::initialize();
    assert_eq!(unsafe { lofi_main() }, 42);
    assert_eq!(arguments.len(), 5);
    let indirect = arguments[2].parse().unwrap();
    let mut effects = 1;
    unsafe {
        match arguments[1].as_str() {
            "integer" => assert_eq!(
                narrow_integer(indirect, arguments[3].parse().unwrap()),
                arguments[4].parse::<i32>().unwrap()
            ),
            "control" => {
                let mode = arguments[3].parse().unwrap();
                effects = mode % 2;
                assert_eq!(
                    narrow_control(indirect, mode),
                    arguments[4].parse::<i32>().unwrap()
                );
            }
            _ => assert!(support::same_float(
                f64::from(narrow_float(indirect, support::number(&arguments[3]))),
                support::number(&arguments[4])
            )),
        }
        assert_eq!(effect_count(), effects);
    }
    support::finish(0);
}
