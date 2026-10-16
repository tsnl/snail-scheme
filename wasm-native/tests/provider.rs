#[unsafe(export_name = "example_hide")]
pub extern "C" fn hide(value: i64) -> i64 {
    std::hint::black_box(value)
}
