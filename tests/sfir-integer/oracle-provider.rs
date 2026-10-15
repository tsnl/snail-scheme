use std::sync::Mutex;

// ---- Scalar strings cross only the diagnostic boundary ----

pub static ARGUMENTS: Mutex<[String; 2]> = Mutex::new([String::new(), String::new()]);
pub static OUTPUT: Mutex<String> = Mutex::new(String::new());

#[unsafe(export_name = "argument_length")]
pub extern "C" fn argument_length(index: i32) -> i64 {
    ARGUMENTS.lock().unwrap()[usize::try_from(index).unwrap()].len() as i64
}

#[unsafe(export_name = "argument_character")]
pub extern "C" fn argument_character(index: i32, at: i64) -> u32 {
    ARGUMENTS.lock().unwrap()[usize::try_from(index).unwrap()].as_bytes()
        [usize::try_from(at).unwrap()] as u32
}

#[unsafe(export_name = "emit_character")]
pub extern "C" fn emit_character(scalar: u32) {
    assert!(scalar < 128);
    OUTPUT.lock().unwrap().push(char::from_u32(scalar).unwrap());
}
// Fixture-only Rust calls share the provider's owned argument and result buffers.
#[unsafe(no_mangle)]
pub fn oracle_arguments(left: &str, right: &str) {
    *ARGUMENTS.lock().unwrap() = [left.into(), right.into()];
    OUTPUT.lock().unwrap().clear();
}
#[unsafe(no_mangle)]
pub fn oracle_output() -> String {
    OUTPUT.lock().unwrap().clone()
}
