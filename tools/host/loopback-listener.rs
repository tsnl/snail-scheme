//! Bind an ephemeral loopback port, then transfer its socket to Scheme.
//! Chibi exposes accept/listen but does not expose getsockname for port zero.

use std::{
    ffi::OsStr,
    io,
    net::TcpListener,
    os::{fd::AsRawFd, unix::process::CommandExt},
    process::Command,
};

// ---- Socket ownership passes across exec ----

fn bind_loopback(port: &OsStr) -> io::Result<TcpListener> {
    let port: u16 = port
        .to_str()
        .and_then(|text| text.parse().ok())
        .ok_or_else(|| io::Error::other("invalid loopback port"))?;
    TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, port))
}

fn inherit_listener(listener: &TcpListener, command: &mut Command) -> io::Result<()> {
    // Chibi's cooperative accept yields on EAGAIN while request threads run.
    listener.set_nonblocking(true)?;
    let descriptor = listener.as_raw_fd();
    if unsafe { libc::fcntl(descriptor, libc::F_SETFD, 0) } < 0 {
        return Err(io::Error::last_os_error());
    }
    command
        .env("SNAIL_TRACE_LISTENER", descriptor.to_string())
        .env(
            "SNAIL_TRACE_PORT",
            listener.local_addr()?.port().to_string(),
        );
    Ok(())
}

fn listen_and_exec() -> io::Result<()> {
    let arguments: Vec<_> = std::env::args_os().collect();
    if arguments.len() < 4 || arguments[2] != "--" {
        return Err(io::Error::other("expected PORT -- PROGRAM ARGS..."));
    }
    let listener = bind_loopback(&arguments[1])?;
    let mut command = Command::new(&arguments[3]);
    command.args(&arguments[4..]);
    inherit_listener(&listener, &mut command)?;
    Err(command.exec())
}

fn main() {
    if let Err(error) = listen_and_exec() {
        eprintln!("view-traces: {error}");
        std::process::exit(1);
    }
}
