// ---- Foreign declarations exercise every scalar ABI representation ----

#[unsafe(export_name = "mixed_scalar")]
pub extern "C" fn mixed_scalar(a: i32, b: i64, c: f32, d: f64) -> i64 {
    assert_eq!((a, b, c, d), (-17, i64::MIN + 7, 1.25, -2.5));
    i64::MAX - 5
}

#[unsafe(export_name = "scalar_f32")]
pub extern "C" fn scalar_f32(value: f32) -> f32 {
    assert_eq!(value, 1.25);
    value
}

#[unsafe(export_name = "scalar_f64")]
pub extern "C" fn scalar_f64(value: i64, real: f64) -> f64 {
    assert_eq!((value, real), (i64::MAX - 5, -2.5));
    3.5
}

#[unsafe(export_name = "scalar_i32")]
pub extern "C" fn scalar_i32(value: i32) -> i32 {
    value
}

#[unsafe(export_name = "scalar_unit")]
pub extern "C" fn scalar_unit(value: i32) {
    assert_eq!(value, 0x1f600);
}
