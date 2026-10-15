// ---- Effects escape the guest before a terminal initialization failure ----

#[unsafe(export_name = "record")]
pub extern "C" fn record(value: i64) {
    println!("effect:{value}");
}
