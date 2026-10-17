//! Record the explicitly owned compiler process, then replace it with Chibi.
use std::os::unix::process::CommandExt;

fn main() {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    if arguments.first().map(String::as_str) != Some("-q") {
        let record =
            serde_json::json!({"pid": std::process::id(), "directory": arguments.last().unwrap()});
        std::fs::write(
            std::env::var("LOFI_SERVICE_TEST_HOST").unwrap(),
            record.to_string(),
        )
        .unwrap();
    }
    let error = std::process::Command::new(std::env::var("CHIBI").unwrap_or("chibi-scheme".into()))
        .args(arguments)
        .exec();
    panic!("cannot execute Chibi: {error}");
}
