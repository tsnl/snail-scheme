//! Owned Linux process lifetimes for build and test commands.
//!
//! A subreaper owns orphaned descendants; the unreaped leader reserves the
//! process-group identity through the final kill. No guest code is loaded here.

use std::{
    ffi::OsString,
    io,
    os::unix::process::CommandExt,
    process::Command,
    sync::atomic::{AtomicBool, Ordering},
    time::{Duration, Instant},
};

static STOPPED: AtomicBool = AtomicBool::new(false);

// ---- Owned process groups ----

extern "C" fn stop(_signal: i32) {
    STOPPED.store(true, Ordering::Relaxed);
}

fn own_lifetime(parent: libc::pid_t) -> io::Result<()> {
    STOPPED.store(false, Ordering::Relaxed);
    let mut action: libc::sigaction = unsafe { std::mem::zeroed() };
    action.sa_sigaction = stop as *const () as usize;
    unsafe {
        libc::sigemptyset(&mut action.sa_mask);
        if libc::sigaction(libc::SIGTERM, &action, std::ptr::null_mut()) != 0
            || libc::sigaction(libc::SIGINT, &action, std::ptr::null_mut()) != 0
            || libc::signal(libc::SIGCHLD, libc::SIG_DFL) == libc::SIG_ERR
            || libc::prctl(libc::PR_SET_CHILD_SUBREAPER, 1) != 0
            || libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) != 0
        {
            return Err(io::Error::last_os_error());
        }
        if libc::getppid() != parent {
            STOPPED.store(true, Ordering::Relaxed);
        }
    }
    Ok(())
}

#[derive(Clone, Default)]
struct Cleanup {
    wait_status: Option<i32>,
    descendants_gone: bool,
    unexpected_descendants: Vec<libc::pid_t>,
    executing_descendants: Vec<libc::pid_t>,
}

impl Cleanup {
    fn exit_code(&self) -> Option<i32> {
        self.wait_status
            .filter(|&status| libc::WIFEXITED(status))
            .map(|status| libc::WEXITSTATUS(status))
    }

    fn signal(&self) -> Option<i32> {
        self.wait_status
            .filter(|&status| libc::WIFSIGNALED(status))
            .map(|status| libc::WTERMSIG(status))
    }

    fn status(&self) -> i32 {
        if self.descendants_gone {
            self.exit_code().unwrap_or(1)
        } else {
            1
        }
    }
}

struct ChildGroup {
    pid: libc::pid_t,
    // An unreaped child reserves its PID, even after exit. Once released, no
    // process-group signal may use that identity again.
    leader_owned: bool,
    cleanup: Option<Cleanup>,
}

impl ChildGroup {
    fn spawn(command: &mut Command) -> io::Result<Self> {
        let parent = unsafe { libc::getpid() };
        unsafe {
            command.pre_exec(move || {
                libc::signal(libc::SIGTERM, libc::SIG_DFL);
                libc::signal(libc::SIGINT, libc::SIG_DFL);
                libc::signal(libc::SIGPIPE, libc::SIG_IGN);
                if libc::setpgid(0, 0) != 0
                    || libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGKILL) != 0
                    || libc::getppid() != parent
                {
                    return Err(io::Error::last_os_error());
                }
                Ok(())
            });
        }
        Ok(Self {
            pid: command.spawn()?.id() as libc::pid_t,
            leader_owned: true,
            cleanup: None,
        })
    }

    fn exited(&mut self) -> io::Result<bool> {
        if !self.leader_owned {
            return Ok(true);
        }
        match child_exited(self.pid)? {
            Some(exited) => Ok(exited),
            None => {
                self.leader_owned = false;
                Ok(true)
            }
        }
    }

    fn signal(&self, signal: i32) {
        if self.leader_owned {
            unsafe { libc::kill(-self.pid, signal) };
        }
    }

    fn finish(&mut self) -> Cleanup {
        if let Some(cleanup) = &self.cleanup {
            return cleanup.clone();
        }
        let mut cleanup = Cleanup::default();
        if self.exited().unwrap_or(false) {
            cleanup.unexpected_descendants = running_children()
                .unwrap_or_default()
                .into_iter()
                .filter(|&pid| pid != self.pid)
                .collect();
        }
        self.signal(libc::SIGKILL); // The last group signal precedes reaping its leader.
        self.collect_children(&mut cleanup, Instant::now() + Duration::from_secs(2));
        self.cleanup = Some(cleanup.clone());
        cleanup
    }

    fn collect_children(&mut self, cleanup: &mut Cleanup, deadline: Instant) {
        while Instant::now() < deadline {
            match self.reap_ready(cleanup, deadline) {
                Ok(true) => {
                    cleanup.descendants_gone = true;
                    return;
                }
                Err(_) => break,
                Ok(false) => {}
            }
            // Children that changed group become direct adopted children when
            // their parents exit. Signal only identities still owned by us.
            if kill_owned_children().is_err() {
                break;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        cleanup.executing_descendants = running_children().unwrap_or_default();
        cleanup.descendants_gone = self.reap_ready(cleanup, deadline).unwrap_or(false);
        if cleanup.descendants_gone {
            cleanup.executing_descendants.clear();
        }
    }

    fn reap_ready(&mut self, cleanup: &mut Cleanup, deadline: Instant) -> io::Result<bool> {
        loop {
            let mut status = 0;
            let pid = unsafe { libc::waitpid(-1, &mut status, libc::WNOHANG) };
            if pid == self.pid {
                self.leader_owned = false;
                cleanup.wait_status = Some(status);
            }
            if pid == 0 {
                return Ok(false);
            }
            if pid < 0 {
                let error = io::Error::last_os_error();
                if error.raw_os_error() == Some(libc::ECHILD) {
                    self.leader_owned = false;
                    return Ok(true);
                }
                if error.kind() != io::ErrorKind::Interrupted {
                    return Err(error);
                }
            }
            if Instant::now() >= deadline {
                return Ok(false);
            }
        }
    }
}

impl Drop for ChildGroup {
    fn drop(&mut self) {
        self.finish();
    }
}

fn child_exited(pid: libc::pid_t) -> io::Result<Option<bool>> {
    let mut information: libc::siginfo_t = unsafe { std::mem::zeroed() };
    let result = unsafe {
        libc::waitid(
            libc::P_PID,
            pid as u32,
            &mut information,
            libc::WEXITED | libc::WNOHANG | libc::WNOWAIT,
        )
    };
    if result == 0 {
        return Ok(Some(unsafe { information.si_pid() } == pid));
    }
    let error = io::Error::last_os_error();
    match error.raw_os_error() {
        Some(libc::ECHILD) => Ok(None),
        Some(libc::EINTR) => Ok(Some(false)),
        _ => Err(error),
    }
}

fn owned_children() -> io::Result<Vec<libc::pid_t>> {
    // This dedicated supervisor is single-threaded and owns every child. The
    // kernel list includes adopted orphans, independently of process groups.
    let path = format!("/proc/self/task/{}/children", unsafe { libc::getpid() });
    std::fs::read_to_string(path)?
        .split_whitespace()
        .map(|pid| {
            pid.parse()
                .map_err(|_| io::Error::other("invalid kernel child identifier"))
        })
        .collect()
}

fn running_children() -> io::Result<Vec<libc::pid_t>> {
    let mut running = Vec::new();
    for pid in owned_children()? {
        if child_exited(pid)? == Some(false) {
            running.push(pid);
        }
    }
    Ok(running)
}

fn kill_owned_children() -> io::Result<()> {
    for pid in running_children()? {
        // No other thread reaps children. Exiting between this check and kill
        // retains a zombie and therefore cannot recycle the checked identity.
        unsafe { libc::kill(pid, libc::SIGKILL) };
    }
    Ok(())
}

fn supervise_command(mut command: Command, timeout: Duration) -> io::Result<i32> {
    let record = std::env::var_os("SNAIL_PROCESS_RECORD");
    command.env_remove("SNAIL_PROCESS_RECORD");
    let mut child = ChildGroup::spawn(&mut command)?;
    record_process(record.as_deref(), child.pid, &Cleanup::default(), false)?;
    let timed_out = command_lifetime(&mut child, timeout)?;
    let cleanup = child.finish();
    record_process(record.as_deref(), child.pid, &cleanup, timed_out)?;
    Ok(if timed_out { 124 } else { cleanup.status() })
}

fn command_lifetime(child: &mut ChildGroup, timeout: Duration) -> io::Result<bool> {
    let start = Instant::now();
    let mut stopping = None;
    while !child.exited()? {
        if !timeout.is_zero() && start.elapsed() >= timeout {
            eprintln!("command timed out");
            return Ok(true);
        }
        if STOPPED.load(Ordering::Relaxed) && stopping.is_none() {
            child.signal(libc::SIGTERM);
            stopping = Some(Instant::now());
        }
        if stopping.is_some_and(|start| start.elapsed() >= Duration::from_secs(1)) {
            return Ok(false);
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    Ok(false)
}

fn record_process(
    path: Option<&std::ffi::OsStr>,
    pid: libc::pid_t,
    cleanup: &Cleanup,
    timed_out: bool,
) -> io::Result<()> {
    if let Some(path) = path {
        let exit_code = cleanup
            .exit_code()
            .map_or("null".into(), |value| value.to_string());
        let signal = cleanup
            .signal()
            .map_or("null".into(), |value| value.to_string());
        let wait_status = cleanup
            .wait_status
            .map_or("null".into(), |value| value.to_string());
        std::fs::write(
            path,
            format!(
                concat!(
                    "{{\"pid\":{pid},\"pgid\":{pid},\"descendants_gone\":{},\"timed_out\":{timed_out},",
                    "\"unexpected_descendants\":{:?},\"executing_descendants\":{:?},",
                    "\"exit_code\":{exit_code},\"signal\":{signal},\"wait_status\":{wait_status}}}\n"
                ),
                cleanup.descendants_gone,
                cleanup.unexpected_descendants,
                cleanup.executing_descendants,
                pid = pid,
                timed_out = timed_out,
                exit_code = exit_code,
                signal = signal,
                wait_status = wait_status
            ),
        )?;
    }
    Ok(())
}

// ---- Supervisor command line ----

fn argument<T: std::str::FromStr>(arguments: &[OsString], index: usize) -> io::Result<T> {
    arguments
        .get(index)
        .and_then(|text| text.to_str())
        .and_then(|text| text.parse().ok())
        .ok_or_else(|| io::Error::other("invalid process supervisor arguments"))
}

fn command_mode(arguments: &[OsString]) -> io::Result<i32> {
    if arguments.len() < 5 || arguments[1] != "--command" || arguments[3] != "--" {
        return Err(io::Error::other(
            "expected --command TIMEOUT_MS -- PROGRAM [ARGS]",
        ));
    }
    own_lifetime(unsafe { libc::getppid() })?;
    if STOPPED.load(Ordering::Relaxed) {
        return Ok(1);
    }
    let timeout = Duration::from_millis(argument(arguments, 2)?);
    let mut command = Command::new(&arguments[4]);
    command.args(&arguments[5..]);
    supervise_command(command, timeout)
}

fn main() {
    let arguments: Vec<OsString> = std::env::args_os().collect();
    let status = command_mode(&arguments).unwrap_or_else(|error| {
        eprintln!("process supervisor: {error}");
        1
    });
    std::process::exit(status);
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn owned_process_test_child() {
        let Ok(mode) = std::env::var("SNAIL_PROCESS_TEST") else {
            return;
        };
        own_lifetime(unsafe { libc::getppid() }).unwrap();
        let mut command = Command::new("sh");
        command.args(["-c", &mode]);
        let status = supervise_command(command, Duration::from_millis(200)).unwrap();
        std::process::exit(status);
    }

    fn process_test(command: &str) -> std::process::Output {
        Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "tests::owned_process_test_child", "--nocapture"])
            .env("SNAIL_PROCESS_TEST", command)
            .output()
            .unwrap()
    }

    #[test]
    fn process_lifetime_preserves_status_and_bounds_stalled_execution() {
        assert_eq!(process_test("exit 7").status.code(), Some(7));
        let start = Instant::now();
        let stalled = process_test("sleep 60");
        assert_eq!(stalled.status.code(), Some(124));
        assert!(start.elapsed() < Duration::from_secs(5));
        assert!(String::from_utf8_lossy(&stalled.stderr).contains("timed out"));
    }

    #[test]
    fn completed_leader_does_not_leave_a_descendant() {
        let path =
            std::env::temp_dir().join(format!("snail-owned-descendant-{}", std::process::id()));
        let result = process_test(&format!("sleep 60 & echo $! > '{}'", path.display()));
        assert!(
            result.status.success(),
            "{}",
            String::from_utf8_lossy(&result.stderr)
        );
        let pid: i32 = std::fs::read_to_string(&path)
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        std::fs::remove_file(path).unwrap();
        assert_eq!(unsafe { libc::kill(pid, 0) }, -1);
        assert_eq!(io::Error::last_os_error().raw_os_error(), Some(libc::ESRCH));
    }

    #[test]
    fn changed_group_descendants_are_recorded_killed_and_reaped() {
        let base = std::env::temp_dir().join(format!("snail-changed-group-{}", std::process::id()));
        let (pidfile, record) = (base.with_extension("pid"), base.with_extension("json"));
        let command = format!(
            "setsid sh -c 'echo $$ > \"$1\"; exec sleep 60' sh '{}' & while [ ! -s '{}' ]; do sleep 0.01; done",
            pidfile.display(),
            pidfile.display()
        );
        let start = Instant::now();
        let result = Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "tests::owned_process_test_child", "--nocapture"])
            .env("SNAIL_PROCESS_TEST", command)
            .env("SNAIL_PROCESS_RECORD", &record)
            .output()
            .unwrap();
        assert!(
            result.status.success(),
            "{}",
            String::from_utf8_lossy(&result.stderr)
        );
        assert!(start.elapsed() < Duration::from_secs(3));
        let pid: i32 = std::fs::read_to_string(&pidfile)
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        let evidence = std::fs::read_to_string(&record).unwrap();
        assert!(
            evidence.contains(&format!("\"unexpected_descendants\":[{pid}]")),
            "{evidence}"
        );
        assert!(evidence.contains("\"descendants_gone\":true"), "{evidence}");
        assert!(
            evidence.contains("\"executing_descendants\":[]"),
            "{evidence}"
        );
        assert!(
            evidence.contains("\"exit_code\":0,\"signal\":null"),
            "{evidence}"
        );
        assert_eq!(unsafe { libc::kill(pid, 0) }, -1);
        assert_eq!(io::Error::last_os_error().raw_os_error(), Some(libc::ESRCH));
        std::fs::remove_file(pidfile).unwrap();
        std::fs::remove_file(record).unwrap();
    }
}
