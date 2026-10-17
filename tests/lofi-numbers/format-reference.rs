fn float_text(number: f64) -> String {
    if number.is_nan() {
        "+nan.0".into()
    } else if number == f64::INFINITY {
        "+inf.0".into()
    } else if number == f64::NEG_INFINITY {
        "-inf.0".into()
    } else {
        finite_float_text(number)
    }
}

fn finite_float_text(number: f64) -> String {
    let mut text = format!("{number:?}");
    // Match the bootstrap writer's explicit positive exponent. Both spellings
    // read identically, but compiler output is compared byte for byte.
    if let Some(index) = text.find('e') {
        if text.as_bytes()[index + 1] != b'-' {
            text.insert(index + 1, '+');
        }
    }
    text
}

fn main() {
    let input = std::fs::read_to_string(std::env::args().nth(1).unwrap()).unwrap();
    for line in input.lines() {
        println!(
            "{}",
            float_text(f64::from_bits(u64::from_str_radix(line, 16).unwrap()))
        );
    }
}
