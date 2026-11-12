fn main() {
    if std::env::var("CARGO_CFG_TARGET_ARCH").as_deref() == Ok("wasm32") {
        // All separately compiled libraries allocate code handles in this one
        // table. Rust's entries keep their indices; Snail appends its entries.
        println!("cargo:rustc-link-arg=--export-table");
        println!("cargo:rustc-link-arg=--growable-table");
    }
}
