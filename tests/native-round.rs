#[path = "native-support.rs"]
mod support;
unsafe extern "C" {
    #[link_name = "wasm.main"]
    fn guest_main();
    #[link_name = "wasm.worker"]
    fn rounded(p0: f64) -> f64;
    #[link_name = "wasm.round32"]
    fn rounded32(p0: f32) -> f32;
    #[link_name = "wasm.view64"]
    fn concrete(p0: f64) -> f64;
    #[link_name = "wasm.view32"]
    fn concrete32(p0: f32) -> f32;
}

// ---- Ties-to-even preserves IEEE categories and the sign of zero ----

fn main() {
    support::initialize();
    unsafe { guest_main() };
    let inputs = [
        f64::NEG_INFINITY,
        -3.5,
        -2.5,
        -1.5,
        -0.5,
        -0.0,
        0.0,
        0.5,
        1.5,
        2.5,
        3.5,
        f64::INFINITY,
    ];
    let expected = [
        f64::NEG_INFINITY,
        -4.0,
        -2.0,
        -2.0,
        -0.0,
        -0.0,
        0.0,
        0.0,
        2.0,
        2.0,
        4.0,
        f64::INFINITY,
    ];
    for (input, target) in inputs.into_iter().zip(expected) {
        unsafe {
            for actual in [
                rounded(input),
                concrete(input),
                f64::from(rounded32(input as f32)),
                f64::from(concrete32(input as f32)),
            ] {
                assert!(
                    support::same_float(actual, target),
                    "{input} -> {actual} != {target}"
                );
            }
        }
    }
    assert!(unsafe { rounded(f64::NAN).is_nan() && rounded32(f32::NAN).is_nan() });
    support::finish(0);
}
