//! Report Rust's native Unicode casing to the Scheme table generator.

// ---- Scalar casing records ----

fn codes(text: &str) -> String {
    text.chars()
        .map(|character| format!("{:x}", character as u32))
        .collect::<Vec<_>>()
        .join(",")
}

fn main() {
    let (major, minor, patch) = char::UNICODE_VERSION;
    println!("{major}.{minor}.{patch}");
    for character in (0..=0x10ffff).filter_map(char::from_u32) {
        let upper: String = character.to_uppercase().collect();
        let lower: String = character.to_lowercase().collect();
        if upper != character.to_string() || lower != character.to_string() {
            println!("{:x};{};{}", character as u32, codes(&upper), codes(&lower));
        }
    }
}
