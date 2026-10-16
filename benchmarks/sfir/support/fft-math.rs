// ---- Native Wasm sine provider ----

// Only F64 scalars cross this boundary. Scheme vectors stay in the consumer's
// WasmGC heap; the Rust module receives no managed values or references.
#[unsafe(export_name = "snail_sin")]
pub extern "C" fn snail_sin(value: f64) -> f64 {
    value.sin()
}
