#[unsafe(export_name = "tick")]
pub extern "C" fn tick() -> f64 {
    0.0
}
#[unsafe(export_name = "mark")]
pub extern "C" fn mark(_value: i64) {}
