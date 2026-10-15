// ---- Scalar observations preserve integer precision and binary64 bits ----

#[unsafe(export_name = "emit_i64")]
pub extern "C" fn emit_i64(value: i64) {
    println!("i:{value}");
}

#[unsafe(export_name = "emit_char")]
pub extern "C" fn emit_char(value: u32) {
    println!("c:{value}");
}

#[unsafe(export_name = "emit_f64")]
pub extern "C" fn emit_f64(value: f64) {
    if value.is_nan() {
        println!("f:nan");
    } else {
        println!("f:{}", value.to_bits());
    }
}
