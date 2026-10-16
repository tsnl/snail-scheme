//! Low-level process-loss probe: reap orphaned native owners after host SIGKILL.
use std::path::Path;
use std::time::{Duration, Instant};
unsafe extern "C" {
    fn prctl(option: i32, ...) -> i32;
    fn waitpid(pid: i32, status: *mut i32, options: i32) -> i32;
}

fn gone(pid: u32) {
    let deadline = Instant::now() + Duration::from_secs(5);
    while Path::new(&format!("/proc/{pid}")).exists() && Instant::now() < deadline {
        unsafe {
            waitpid(-1, std::ptr::null_mut(), 1);
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    assert!(
        !Path::new(&format!("/proc/{pid}")).exists(),
        "owned process remains: {pid}"
    );
}

fn main() {
    let arguments: Vec<String> = std::env::args().collect();
    let directory = Path::new(&arguments[1]);
    assert_eq!(unsafe { prctl(36, 1, 0, 0, 0) }, 0);
    let mut host = std::process::Command::new(&arguments[2])
        .args(&arguments[3..])
        .stdout(std::fs::File::create(directory.join("host-loss.stdout")).unwrap())
        .stderr(std::fs::File::create(directory.join("host-loss.stderr")).unwrap())
        .spawn()
        .unwrap();
    let ready = directory.join("host-ready");
    let deadline = Instant::now() + Duration::from_secs(60);
    while !ready.exists() && host.try_wait().unwrap().is_none() && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(10));
    }
    if !ready.exists() {
        let _ = host.kill();
        let _ = host.wait();
        panic!(
            "host never became ready: {}",
            std::fs::read_to_string(directory.join("host-loss.stderr")).unwrap()
        );
    }
    let process: serde_json::Value =
        serde_json::from_slice(&std::fs::read(ready).unwrap()).unwrap();
    host.kill().unwrap();
    host.wait().unwrap();
    gone(process["pid"].as_u64().unwrap() as u32);
    gone(
        std::fs::read_to_string(directory.join("host-loss-live-child"))
            .unwrap()
            .trim()
            .parse()
            .unwrap(),
    );
}
