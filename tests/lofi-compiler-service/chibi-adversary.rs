//! A deliberately uncooperative compiler host tests owned process deadlines.
use std::io::{BufRead, Write};
unsafe extern "C" {
    fn signal(signal: i32, handler: usize) -> usize;
}

fn wait_forever() -> ! {
    loop {
        std::thread::sleep(std::time::Duration::from_secs(60));
    }
}

fn main() {
    unsafe {
        signal(15, 1);
    }
    if std::env::args().any(|value| value == "--descendant") {
        println!("ready");
        wait_forever();
    }
    let mut child = std::process::Command::new(std::env::current_exe().unwrap())
        .arg("--descendant")
        .stdout(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    let mut ready = String::new();
    std::io::BufReader::new(child.stdout.take().unwrap())
        .read_line(&mut ready)
        .unwrap();
    assert_eq!(ready, "ready\n");
    let directory = std::path::PathBuf::from(std::env::args().last().unwrap());
    let record =
        serde_json::json!({"pid":std::process::id(),"descendant":child.id(),"directory":directory});
    std::fs::write(
        std::env::var("LOFI_SERVICE_TEST_HOST").unwrap(),
        record.to_string(),
    )
    .unwrap();
    let mode = std::env::var("LOFI_SERVICE_TEST_MODE").unwrap();
    let mut response = std::fs::OpenOptions::new()
        .write(true)
        .open(directory.join("responses"))
        .unwrap();
    eprintln!("owned host diagnostic sentinel");
    if mode.ends_with("request") || mode == "ignore-close" {
        response.write_all(b"[true,\"ready\"]\n").unwrap();
        let mut request = String::new();
        std::io::BufReader::new(std::fs::File::open(directory.join("requests")).unwrap())
            .read_line(&mut request)
            .unwrap();
    }
    if mode == "progress-request" {
        eprintln!("[lofi] blocked phase started");
        while !directory.join("release").exists() {
            std::thread::sleep(std::time::Duration::from_millis(5));
        }
        eprintln!("{}", "x".repeat(12_000));
        eprintln!("[lofi] burst completed");
        response.write_all(b"[true,1]\n").unwrap();
    }
    if mode.starts_with("noisy") {
        loop {
            response.write_all(&[b' '; 65_536]).unwrap();
        }
    }
    wait_forever();
}
