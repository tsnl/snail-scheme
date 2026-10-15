#[path = "../native-support.rs"]
mod support;
unsafe extern "C" {
    #[link_name = "wasm.main"]
    fn guest_main() -> i64;
    #[link_name = "wasm.encode-scalar"]
    fn encode_scalar(value: i64) -> i64;
    #[link_name = "wasm.decode-scalar"]
    fn decode_scalar(value: i64) -> i64;
}

// ---- Portable little-endian records avoid unaligned loads ----

fn main() {
    let arguments = support::initialize();
    assert_eq!(arguments.len(), 2);
    assert_eq!(unsafe { guest_main() }, 0);
    let records = std::fs::read(&arguments[1]).unwrap();
    assert_eq!(records.len() % 12, 0);
    for row in records.chunks_exact(12) {
        let scalar = i64::from(u32::from_le_bytes(row[..4].try_into().unwrap()));
        let packed = i64::from_le_bytes(row[4..].try_into().unwrap());
        assert_eq!(unsafe { encode_scalar(scalar) }, packed);
        assert_eq!(unsafe { decode_scalar(packed) }, scalar);
    }
    println!("scalars {}", records.len() / 12);
    support::finish(0);
}
