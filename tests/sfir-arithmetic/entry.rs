#[path = "../native-support.rs"]
mod support;
unsafe extern "C" {
    #[link_name = "wasm.main"]
    fn sfir_main() -> i32;
    #[link_name = "wasm.constant-arithmetic"]
    fn constant_arithmetic(p0: i32);
    #[link_name = "wasm.calculate-i32"]
    fn calculate_i32(p0: i32, p1: i32, p2: i32, p3: i32) -> i32;
    #[link_name = "wasm.calculate-i64"]
    fn calculate_i64(p0: i32, p1: i32, p2: i64, p3: i64) -> i64;
    #[link_name = "wasm.calculate-f32"]
    fn calculate_f32(p0: i32, p1: i32, p2: f32, p3: f32) -> f32;
    #[link_name = "wasm.calculate-f64"]
    fn calculate_f64(p0: i32, p1: i32, p2: f64, p3: f64) -> f64;
    #[link_name = "wasm.discard-i32"]
    fn discard_i32(p0: i32, p1: i32, p2: i32, p3: i32, p4: i32);
    #[link_name = "wasm.discard-i64"]
    fn discard_i64(p0: i32, p1: i32, p2: i32, p3: i64, p4: i64);
    #[link_name = "wasm.discard-f32"]
    fn discard_f32(p0: i32, p1: i32, p2: i32, p3: f32, p4: f32);
    #[link_name = "wasm.discard-f64"]
    fn discard_f64(p0: i32, p1: i32, p2: i32, p3: f64, p4: f64);
}

// ---- The expected result and operand effects come from independent fixtures ----

unsafe fn check_value(arguments: &[String], route: i32, operation: i32) {
    let left = &arguments[5];
    let right = &arguments[6];
    let expected = &arguments[7];
    unsafe {
        match arguments[2].as_str() {
            "i32" => assert_eq!(
                calculate_i32(
                    route,
                    operation,
                    left.parse().unwrap(),
                    right.parse().unwrap()
                ),
                expected.parse::<i32>().unwrap()
            ),
            "i64" => assert_eq!(
                calculate_i64(
                    route,
                    operation,
                    left.parse().unwrap(),
                    right.parse().unwrap()
                ),
                expected.parse::<i64>().unwrap()
            ),
            "f32" => assert!(support::same_float(
                f64::from(calculate_f32(
                    route,
                    operation,
                    support::number(left) as f32,
                    support::number(right) as f32
                )),
                support::number(expected)
            )),
            "f64" => assert!(support::same_float(
                calculate_f64(
                    route,
                    operation,
                    support::number(left),
                    support::number(right)
                ),
                support::number(expected)
            )),
            _ => panic!("unknown arithmetic kind"),
        }
    }
}

unsafe fn discard_value(arguments: &[String], route: i32, operation: i32) {
    let selected = i32::from(arguments[1] == "discard");
    let left = &arguments[5];
    let right = &arguments[6];
    unsafe {
        match arguments[2].as_str() {
            "i32" => discard_i32(
                selected,
                route,
                operation,
                left.parse().unwrap(),
                right.parse().unwrap(),
            ),
            "i64" => discard_i64(
                selected,
                route,
                operation,
                left.parse().unwrap(),
                right.parse().unwrap(),
            ),
            "f32" => discard_f32(
                selected,
                route,
                operation,
                support::number(left) as f32,
                support::number(right) as f32,
            ),
            "f64" => discard_f64(
                selected,
                route,
                operation,
                support::number(left),
                support::number(right),
            ),
            _ => panic!("unknown arithmetic kind"),
        }
    }
}

fn main() {
    let arguments = support::initialize();
    assert_eq!(unsafe { sfir_main() }, 42);
    assert_eq!(arguments.len(), 8);
    let route = arguments[3].parse().unwrap();
    let operation = arguments[4].parse().unwrap();
    unsafe {
        match arguments[1].as_str() {
            "constant" => constant_arithmetic(operation),
            "value" => check_value(&arguments, route, operation),
            _ => discard_value(&arguments, route, operation),
        }
    }
    support::finish(0);
}
