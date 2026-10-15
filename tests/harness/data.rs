//! Expand independent fixtures into the exact transport formats used by guests.
use serde_json::Value;
use std::io::{BufWriter, Write};
use std::path::Path;

// ---- Complete independent Unicode scalar encodings ----

fn unicode(path: &Path) {
    let mut output = BufWriter::new(std::fs::File::create(path).unwrap());
    let mut count = 0;
    for scalar in (0..=0x10ffff).filter_map(char::from_u32) {
        let mut bytes = [0; 4];
        let length = scalar.encode_utf8(&mut bytes).len();
        let packed = u64::from(u32::from_le_bytes(bytes)) | ((length as u64) << 32);
        output.write_all(&(scalar as u32).to_le_bytes()).unwrap();
        output.write_all(&packed.to_le_bytes()).unwrap();
        count += 1;
    }
    assert_eq!(count, 1_112_064);
    output.flush().unwrap();
}

// ---- Unicode 16 full folding includes every identity mapping ----

fn folding(source: &Path, directory: &Path) {
    let cases: Value = serde_json::from_slice(&std::fs::read(source).unwrap()).unwrap();
    let overrides = cases["folds"].as_object().unwrap();
    let mut output =
        BufWriter::new(std::fs::File::create(directory.join("fold-scalars.txt")).unwrap());
    for scalar in (0..=0x10ffff).filter(|&code| char::from_u32(code).is_some()) {
        let identity = [Value::from(scalar)];
        let folded = overrides
            .get(&scalar.to_string())
            .map(|v| v.as_array().unwrap().as_slice())
            .unwrap_or(&identity);
        write!(output, "{scalar} {}", folded.len()).unwrap();
        for index in 0..3 {
            write!(
                output,
                " {}",
                folded.get(index).and_then(Value::as_u64).unwrap_or(0)
            )
            .unwrap();
        }
        writeln!(output).unwrap();
    }
    output.flush().unwrap();
}

fn main() {
    let arguments: Vec<String> = std::env::args().collect();
    match arguments[1].as_str() {
        "unicode" => unicode(Path::new(&arguments[2])),
        "folding" => folding(Path::new(&arguments[2]), Path::new(&arguments[3])),
        _ => panic!("expected unicode OUTPUT or folding CORPUS DIRECTORY"),
    }
}
