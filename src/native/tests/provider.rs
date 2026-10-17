unsafe extern "C" {
    fn native_gc_collect();
}

#[unsafe(export_name = "example_hide")]
pub extern "C" fn hide(value: i64) -> i64 {
    unsafe { native_gc_collect() };
    std::hint::black_box(value)
}
