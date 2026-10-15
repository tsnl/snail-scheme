//! Exact scalar messages and owned Linux process lifetimes.
//!
//! The supervisor contains no guest/provider code. Only its exec'd child loads
//! the guest image. A subreaper keeps ownership of orphaned descendants; the
//! unreaped leader reserves the process-group identity through the final kill.

use std::{
    ffi::OsString,
    fs::File,
    io::{self, Read, Write},
    os::{
        fd::{AsFd, AsRawFd, FromRawFd, OwnedFd, RawFd},
        unix::process::CommandExt,
    },
    process::{Command, Stdio},
    sync::atomic::{AtomicBool, Ordering},
    time::{Duration, Instant},
};

const READY: u64 = 0x3152_4946_53;
static STOPPED: AtomicBool = AtomicBool::new(false);

// ---- Exact worker messages ----

/// Run a single guest instance. `initialize` installs the module and invokes
/// its startup export; `entry` accepts exactly `arity` scalar words. Neither
/// callback may unwind. Descriptor ownership transfers from the command line.
pub fn run_guest(
    arity: usize,
    initialize: unsafe extern "C" fn(),
    entry: unsafe extern "C" fn(*const u64) -> u64,
) -> i32 {
    let arguments: Vec<String> = std::env::args().collect();
    if arguments.len() != 5 || arguments[4].parse::<usize>().ok() != Some(arity) {
        return 1;
    }
    let (Ok(request), Ok(response)) =
        (arguments[1].parse::<RawFd>(), arguments[2].parse::<RawFd>())
    else {
        return 1;
    };
    if request < 0 || response < 0 || request == response {
        return 1;
    }
    let mut request = unsafe { File::from_raw_fd(request) };
    let mut response = unsafe { File::from_raw_fd(response) };
    super::initialize_host();
    unsafe { initialize() };
    let status = guest_messages(&mut request, &mut response, arity, entry).map_or(1, |()| 0);
    super::native_finish(status)
}

fn guest_messages(
    request: &mut impl Read,
    response: &mut impl Write,
    arity: usize,
    entry: unsafe extern "C" fn(*const u64) -> u64,
) -> io::Result<()> {
    let mut arguments = vec![0_u64; arity];
    response.write_all(&READY.to_le_bytes())?;
    loop {
        let mut command = [0];
        if request.read_exact(&mut command).is_err() || command[0] == 0 {
            return Ok(());
        }
        if command[0] != 1 {
            return Err(io::Error::other("invalid native request"));
        }
        for word in &mut arguments {
            let mut bytes = [0; 8];
            request.read_exact(&mut bytes)?;
            *word = u64::from_le_bytes(bytes);
        }
        let value = unsafe { entry(arguments.as_ptr()) };
        response.write_all(&value.to_le_bytes())?;
    }
}

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

struct ChildGroup {
    pid: libc::pid_t,
    reaped: bool,
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
            reaped: false,
        })
    }

    fn exited(&self) -> io::Result<bool> {
        let mut information: libc::siginfo_t = unsafe { std::mem::zeroed() };
        let result = unsafe {
            libc::waitid(
                libc::P_PID,
                self.pid as u32,
                &mut information,
                libc::WEXITED | libc::WNOHANG | libc::WNOWAIT,
            )
        };
        if result == 0 {
            return Ok(unsafe { information.si_pid() } == self.pid);
        }
        let error = io::Error::last_os_error();
        if error.kind() == io::ErrorKind::Interrupted {
            Ok(false)
        } else {
            Err(error)
        }
    }

    fn signal(&self, signal: i32) {
        unsafe { libc::kill(-self.pid, signal) };
    }

    fn finish(&mut self) -> i32 {
        if self.reaped {
            return 1;
        }
        self.signal(libc::SIGKILL);
        let mut status = 0;
        wait_for(self.pid, &mut status);
        // Providers are trusted native code. Deliberately escaping the owned
        // process group is unsupported; normal descendants remain killable.
        loop {
            let waited = unsafe { libc::waitpid(-1, std::ptr::null_mut(), 0) };
            if waited < 0 && io::Error::last_os_error().kind() != io::ErrorKind::Interrupted {
                break;
            }
        }
        self.reaped = true;
        if libc::WIFEXITED(status) {
            libc::WEXITSTATUS(status)
        } else {
            1
        }
    }
}

impl Drop for ChildGroup {
    fn drop(&mut self) {
        if !self.reaped {
            self.finish();
        }
    }
}

fn wait_for(pid: libc::pid_t, status: &mut i32) {
    while unsafe { libc::waitpid(pid, status, 0) } < 0 {
        if io::Error::last_os_error().kind() != io::ErrorKind::Interrupted {
            break;
        }
    }
}

fn supervise_command(mut command: Command, timeout: Duration) -> io::Result<i32> {
    let record = std::env::var_os("SNAIL_PROCESS_RECORD");
    command.env_remove("SNAIL_PROCESS_RECORD");
    let mut child = ChildGroup::spawn(&mut command)?;
    record_process(record.as_deref(), child.pid, false, false)?;
    let start = Instant::now();
    let mut stopping = None;
    while !child.exited()? {
        if !timeout.is_zero() && start.elapsed() >= timeout {
            eprintln!("native command timed out");
            child.finish();
            record_process(record.as_deref(), child.pid, true, true)?;
            return Ok(124);
        }
        if STOPPED.load(Ordering::Relaxed) && stopping.is_none() {
            child.signal(libc::SIGTERM);
            stopping = Some(Instant::now());
        }
        if stopping.is_some_and(|start| start.elapsed() >= Duration::from_secs(1)) {
            child.signal(libc::SIGKILL);
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    let status = child.finish();
    record_process(record.as_deref(), child.pid, true, false)?;
    Ok(status)
}

fn record_process(
    path: Option<&std::ffi::OsStr>,
    pid: libc::pid_t,
    descendants_gone: bool,
    timed_out: bool,
) -> io::Result<()> {
    if let Some(path) = path {
        std::fs::write(
            path,
            format!(
                "{{\"pid\":{pid},\"pgid\":{pid},\"descendants_gone\":{descendants_gone},\"timed_out\":{timed_out}}}\n"
            ),
        )?;
    }
    Ok(())
}

// ---- Deadline-aware scalar relay ----

fn pipe() -> io::Result<(OwnedFd, OwnedFd)> {
    let mut descriptors = [-1; 2];
    if unsafe { libc::pipe2(descriptors.as_mut_ptr(), libc::O_CLOEXEC) } != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(unsafe {
        (
            OwnedFd::from_raw_fd(descriptors[0]),
            OwnedFd::from_raw_fd(descriptors[1]),
        )
    })
}

fn inherit_descriptor(fd: RawFd) -> io::Result<()> {
    if unsafe { libc::fcntl(fd, libc::F_SETFD, 0) } < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

struct Relay {
    request: File,
    response: File,
    guest_request: File,
    guest_response: File,
    command: Vec<u8>,
    result: Vec<u8>,
    request_bytes: usize,
    deadline: Option<Instant>,
    timeout: Duration,
    initialized: bool,
    closing: bool,
}

impl Relay {
    fn new(
        request: File,
        response: File,
        guest_request: OwnedFd,
        guest_response: OwnedFd,
        arity: usize,
        timeout: Duration,
    ) -> io::Result<Self> {
        let request_bytes = arity
            .checked_mul(8)
            .and_then(|bytes| bytes.checked_add(1))
            .filter(|&bytes| bytes <= 16 * 1024 * 1024)
            .ok_or_else(|| io::Error::other("native arity exceeds protocol limit"))?;
        Ok(Self {
            request,
            response,
            guest_request: guest_request.into(),
            guest_response: guest_response.into(),
            command: Vec::new(),
            result: Vec::new(),
            request_bytes,
            deadline: Some(Instant::now() + timeout),
            timeout,
            initialized: false,
            closing: false,
        })
    }

    fn step(&mut self) -> io::Result<bool> {
        if self
            .deadline
            .is_some_and(|deadline| Instant::now() >= deadline)
        {
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                if self.initialized {
                    "native invocation timed out"
                } else {
                    "native initialization timed out"
                },
            ));
        }
        let mut polls = [
            libc::pollfd {
                fd: self.request.as_raw_fd(),
                events: libc::POLLIN,
                revents: 0,
            },
            libc::pollfd {
                fd: self.guest_response.as_raw_fd(),
                events: libc::POLLIN,
                revents: 0,
            },
        ];
        if self.closing {
            polls[0].fd = -1;
        } else if self.deadline.is_some() && self.command.is_empty() {
            polls[0].events = 0;
        }
        let count = unsafe { libc::poll(polls.as_mut_ptr(), polls.len() as _, 10) };
        if count < 0 && io::Error::last_os_error().kind() != io::ErrorKind::Interrupted {
            return Err(io::Error::last_os_error());
        }
        if polls[0].revents & (libc::POLLIN | libc::POLLHUP) != 0 && !self.read_request()? {
            return Ok(false);
        }
        if polls[1].revents & (libc::POLLIN | libc::POLLHUP) != 0 && !self.read_response()? {
            return Ok(false);
        }
        Ok(true)
    }

    fn read_request(&mut self) -> io::Result<bool> {
        let needed = if self.command.is_empty() {
            1
        } else {
            self.request_bytes - self.command.len()
        };
        let mut bytes = vec![0; needed.min(8192)];
        let count = self.request.read(&mut bytes)?;
        if count == 0 {
            return Ok(false);
        }
        if self.command.is_empty() {
            if bytes[0] == 0 {
                self.guest_request.write_all(&[0])?;
                self.closing = true;
                self.deadline = Some(Instant::now() + self.timeout);
                return Ok(true);
            }
            if bytes[0] != 1 {
                return Err(io::Error::other("invalid native request"));
            }
            self.deadline = Some(Instant::now() + self.timeout);
        }
        self.command.extend_from_slice(&bytes[..count]);
        if self.command.len() == self.request_bytes {
            self.guest_request.write_all(&self.command)?;
            self.command.clear();
        }
        Ok(true)
    }

    fn read_response(&mut self) -> io::Result<bool> {
        let mut bytes = [0_u8; 8];
        let count = self
            .guest_response
            .read(&mut bytes[..8 - self.result.len()])?;
        if count == 0 {
            return Ok(false);
        }
        self.result.extend_from_slice(&bytes[..count]);
        if self.result.len() != 8 {
            return Ok(true);
        }
        if !self.initialized && self.result != READY.to_le_bytes() {
            return Err(io::Error::other("invalid native initialization response"));
        }
        self.response.write_all(&self.result)?;
        self.result.clear();
        self.initialized = true;
        self.deadline = None;
        Ok(true)
    }
}

fn supervise_worker(
    worker: OsString,
    request: File,
    response: File,
    arity: usize,
    timeout: Duration,
    output: Option<File>,
) -> io::Result<i32> {
    let (child_request, guest_request) = pipe()?;
    let (guest_response, child_response) = pipe()?;
    let mut command = Command::new(worker);
    command.args([
        child_request.as_raw_fd().to_string(),
        child_response.as_raw_fd().to_string(),
        unsafe { libc::getpid() }.to_string(),
        arity.to_string(),
    ]);
    if let Some(output) = output {
        command.stdout(Stdio::from(output));
    }
    let (read_fd, write_fd) = (child_request.as_raw_fd(), child_response.as_raw_fd());
    unsafe {
        command.pre_exec(move || {
            inherit_descriptor(read_fd)?;
            inherit_descriptor(write_fd)
        });
    }
    let mut child = ChildGroup::spawn(&mut command)?;
    drop((child_request, child_response));
    let mut relay = Relay::new(
        request,
        response,
        guest_request,
        guest_response,
        arity,
        timeout,
    )?;
    let result = relay_loop(&mut child, &mut relay);
    let status = child.finish();
    result.map(|()| status)
}

fn relay_loop(child: &mut ChildGroup, relay: &mut Relay) -> io::Result<()> {
    let mut stopping = None;
    loop {
        if STOPPED.load(Ordering::Relaxed) && stopping.is_none() {
            child.signal(libc::SIGTERM);
            stopping = Some(Instant::now());
        }
        if stopping.is_some_and(|start| start.elapsed() >= Duration::from_secs(1)) {
            return Ok(());
        }
        if child.exited()? {
            return Ok(());
        }
        if !relay.step()? {
            return Ok(());
        }
    }
}

// ---- Supervisor command line ----

fn argument<T: std::str::FromStr>(arguments: &[OsString], index: usize) -> io::Result<T> {
    arguments
        .get(index)
        .and_then(|text| text.to_str())
        .and_then(|text| text.parse().ok())
        .ok_or_else(|| io::Error::other("invalid native supervisor arguments"))
}

fn command_mode(arguments: &[OsString]) -> io::Result<i32> {
    if arguments.len() < 5 || arguments[3] != "--" {
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

fn stdio_mode(arguments: &[OsString]) -> io::Result<i32> {
    if !(6..=7).contains(&arguments.len()) {
        return Err(io::Error::other(
            "expected --stdio WORKER ARITY TIMEOUT_MS PARENT_PID [STDOUT_PATH]",
        ));
    }
    own_lifetime(argument(arguments, 5)?)?;
    if STOPPED.load(Ordering::Relaxed) {
        return Ok(1);
    }
    let output = if let Some(path) = arguments.get(6) {
        File::create(path)?
    } else {
        File::from(io::stderr().as_fd().try_clone_to_owned()?)
    };
    let request = unsafe { File::from_raw_fd(0) };
    let response = unsafe { File::from_raw_fd(1) };
    supervise_worker(
        arguments[2].clone(),
        request,
        response,
        argument(arguments, 3)?,
        Duration::from_millis(argument(arguments, 4)?),
        Some(output),
    )
}

fn descriptor_mode(arguments: &[OsString]) -> io::Result<i32> {
    if !(6..=7).contains(&arguments.len()) {
        return Err(io::Error::other(
            "expected WORKER REQUEST_FD RESPONSE_FD PARENT_PID ARITY [TIMEOUT_MS]",
        ));
    }
    own_lifetime(argument(arguments, 4)?)?;
    if STOPPED.load(Ordering::Relaxed) {
        return Ok(1);
    }
    let (request, response): (RawFd, RawFd) = (argument(arguments, 2)?, argument(arguments, 3)?);
    if request < 0 || response < 0 || request == response {
        return Err(io::Error::other("invalid native descriptors"));
    }
    let (request, response) = unsafe { (File::from_raw_fd(request), File::from_raw_fd(response)) };
    let timeout = if arguments.len() == 7 {
        argument(arguments, 6)?
    } else {
        30000
    };
    supervise_worker(
        arguments[1].clone(),
        request,
        response,
        argument(arguments, 5)?,
        Duration::from_millis(timeout),
        None,
    )
}

pub fn supervisor_main() -> i32 {
    let arguments: Vec<OsString> = std::env::args_os().collect();
    let result = match arguments.get(1).and_then(|argument| argument.to_str()) {
        Some("--command") => command_mode(&arguments),
        Some("--stdio") => stdio_mode(&arguments),
        Some(_) => descriptor_mode(&arguments),
        None => Err(io::Error::other("missing native supervisor arguments")),
    };
    result.unwrap_or_else(|error| {
        eprintln!("native supervisor: {error}");
        if error.kind() == io::ErrorKind::TimedOut {
            124
        } else {
            1
        }
    })
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    unsafe extern "C" fn echo(words: *const u64) -> u64 {
        unsafe { *words }
    }

    #[test]
    fn scalar_protocol_preserves_all_bits_and_reports_truncated_calls() {
        let value = 0xfedc_ba98_7654_3210_u64;
        let mut input = vec![1];
        input.extend_from_slice(&value.to_le_bytes());
        input.push(0);
        let mut output = Vec::new();
        guest_messages(&mut &input[..], &mut output, 1, echo).unwrap();
        assert_eq!(&output[..8], &READY.to_le_bytes());
        assert_eq!(&output[8..], &value.to_le_bytes());
        assert!(guest_messages(&mut &[1, 2, 3][..], &mut Vec::new(), 1, echo).is_err());
        assert!(guest_messages(&mut &[9][..], &mut Vec::new(), 1, echo).is_err());
    }

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
            .args([
                "--exact",
                "native::worker::tests::owned_process_test_child",
                "--nocapture",
            ])
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
    fn completed_leader_does_not_leave_a_provider_descendant() {
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
}
