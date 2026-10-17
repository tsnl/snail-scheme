//! Record the mandatory optimizer's exact arguments and resulting module bytes.
use std::io::Write;

fn main() {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    let optimizer = std::env::var("LOFI_TEST_OPTIMIZER").unwrap();
    let status = std::process::Command::new(optimizer)
        .args(&arguments)
        .status()
        .unwrap();
    if !arguments.iter().any(|value| value == "--version") {
        let mut record = serde_json::json!({"command":arguments});
        if status.success()
            && let Some(index) = arguments.iter().position(|value| value == "-o")
        {
            let digest = std::process::Command::new("sha256sum")
                .arg(&arguments[index + 1])
                .output()
                .unwrap();
            assert!(digest.status.success());
            record["sha256"] = String::from_utf8(digest.stdout)
                .unwrap()
                .split_whitespace()
                .next()
                .unwrap()
                .into();
        }
        let mut log = std::fs::OpenOptions::new()
            .append(true)
            .create(true)
            .open(std::env::var("LOFI_TEST_OPTIMIZER_LOG").unwrap())
            .unwrap();
        writeln!(log, "{record}").unwrap();
    }
    std::process::exit(status.code().unwrap_or(1));
}
