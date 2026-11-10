//! Bounded native file reads. The host owns every kernel-visible allocation
//! until that request completes; Wasm owns only a linear reception token.
//! Dropping the token withdraws delivery, not an in-flight kernel operation.

use std::collections::BTreeMap;
use std::time::Duration;
use wasmtime::{Caller, Linker, format_err};

use crate::program::Host;

const MODULE: &str = "snail.runtime.native.async-files";
const MAXIMUM: usize = 16 * 1024 * 1024;
const UNAVAILABLE: i32 = -1;
const INVALID: i32 = -2;
const TOO_LARGE: i32 = -3;
const NOT_FOUND: i32 = -4;
const DENIED: i32 = -5;
const FAILED: i32 = -6;
type Outcome = Result<Vec<u8>, i32>;

/// Staging is synchronous and has one owner. Completed buffers remain owned
/// here until finish copies them into managed Bytes, or cancel discards them.
#[derive(Default)]
pub struct Files {
    closed: bool,
    path: String,
    next: i64,
    ready: BTreeMap<i64, Outcome>,
    waking: Vec<(i64, i64)>,
    held: Vec<u8>,
    #[cfg(target_os = "linux")]
    ring: Option<linux::Ring>,
}

impl Files {
    fn start(&mut self, ticket: i64, maximum: i32) -> wasmtime::Result<i64> {
        if self.closed {
            return Err(format_err!("native file provider is closed"));
        }
        let path = std::mem::take(&mut self.path);
        self.next = self
            .next
            .checked_add(1)
            .ok_or_else(|| format_err!("file request IDs exhausted"))?;
        let id = self.next;
        let limit = usize::try_from(maximum).ok().filter(|n| *n <= MAXIMUM);
        let outcome = match limit {
            Some(limit) if !path.contains('\0') => self.submit(id, ticket, path, limit),
            _ => Err(INVALID),
        };
        if let Err(code) = outcome {
            self.ready.insert(id, Err(code));
            self.waking.push((ticket, id));
        }
        Ok(id)
    }

    #[cfg(target_os = "linux")]
    fn submit(&mut self, id: i64, ticket: i64, path: String, limit: usize) -> Result<(), i32> {
        if self.ring.is_none() {
            self.ring = Some(linux::Ring::new().map_err(|_| UNAVAILABLE)?);
        }
        self.ring.as_mut().unwrap().start(id, ticket, path, limit)
    }

    #[cfg(not(target_os = "linux"))]
    fn submit(&mut self, _: i64, _: i64, _: String, _: usize) -> Result<(), i32> {
        Err(UNAVAILABLE)
    }

    pub fn cancel(&mut self, id: i64) {
        self.ready.remove(&id);
        self.waking.retain(|(_, operation)| *operation != id);
        #[cfg(target_os = "linux")]
        if let Some(ring) = &mut self.ring {
            ring.cancel(id);
        }
    }

    fn finish(&mut self, id: i64) -> wasmtime::Result<i32> {
        self.held.clear();
        match self
            .ready
            .remove(&id)
            .ok_or_else(|| format_err!("file result is not ready"))?
        {
            Ok(bytes) => {
                self.held = bytes;
                Ok(self.held.len() as i32)
            }
            Err(code) => Ok(code),
        }
    }

    pub fn collect(&mut self) -> std::io::Result<Vec<(i64, i64)>> {
        #[cfg(target_os = "linux")]
        if let Some(ring) = &mut self.ring {
            for (id, ticket, result) in ring.collect()? {
                self.ready.insert(id, result);
                self.waking.push((ticket, id));
            }
        }
        Ok(std::mem::take(&mut self.waking))
    }

    pub fn pending(&self) -> bool {
        #[cfg(target_os = "linux")]
        if let Some(ring) = &self.ring {
            return ring.pending();
        }
        false
    }

    pub fn wait(&mut self, timeout: Option<Duration>) -> std::io::Result<()> {
        #[cfg(target_os = "linux")]
        if let Some(ring) = &mut self.ring {
            return ring.wait(timeout);
        }
        if let Some(timeout) = timeout {
            std::thread::sleep(timeout);
        }
        Ok(())
    }

    pub fn close(&mut self) -> std::io::Result<()> {
        self.closed = true;
        self.ready.clear();
        self.waking.clear();
        self.held.clear();
        #[cfg(target_os = "linux")]
        if let Some(ring) = &mut self.ring {
            ring.close()?;
        }
        Ok(())
    }
}

// ---- Scalar imports ----

pub fn define(linker: &mut Linker<Host>) -> wasmtime::Result<()> {
    linker.func_wrap(
        MODULE,
        "path-character",
        |mut caller: Caller<'_, Host>, code: i32| {
            let character =
                char::from_u32(code as u32).ok_or_else(|| format_err!("invalid path scalar"))?;
            caller.data_mut().async_files.path.push(character);
            Ok(())
        },
    )?;
    linker.func_wrap(
        MODULE,
        "start-read",
        |mut caller: Caller<'_, Host>, ticket: i64, limit: i32| {
            caller.data_mut().async_files.start(ticket, limit)
        },
    )?;
    linker.func_wrap(MODULE, "finish", |mut caller: Caller<'_, Host>, id: i64| {
        caller.data_mut().async_files.finish(id)
    })?;
    linker.func_wrap(MODULE, "cancel", |mut caller: Caller<'_, Host>, id: i64| {
        caller.data_mut().async_files.cancel(id);
    })?;
    linker.func_wrap(MODULE, "byte", |caller: Caller<'_, Host>, index: i32| {
        caller
            .data()
            .async_files
            .held
            .get(index as usize)
            .copied()
            .map(i32::from)
            .ok_or_else(|| format_err!("file result byte is out of range"))
    })?;
    Ok(())
}

// ---- Linux completion ownership ----

#[cfg(target_os = "linux")]
mod linux {
    use super::*;
    use io_uring::{IoUring, opcode, squeue, types};
    use std::ffi::CString;
    use std::io;
    use std::mem::ManuallyDrop;
    use std::os::fd::{AsRawFd, FromRawFd, IntoRawFd, OwnedFd};

    enum Phase {
        Opening,
        Reading { file: OwnedFd, used: usize },
        Closing { result: Outcome },
    }

    struct Read {
        ticket: i64,
        receiving: bool,
        path: CString,
        bytes: Vec<u8>,
        limit: usize,
        phase: Phase,
    }

    pub struct Ring {
        ring: IoUring,
        // A syscall failure during shutdown cannot justify freeing a buffer
        // the kernel may still use. Drop drains normally; on a fatal driver
        // failure it retains these allocations until process exit instead.
        reads: ManuallyDrop<BTreeMap<i64, Read>>,
    }

    impl Ring {
        pub fn new() -> io::Result<Self> {
            let ring = IoUring::new(128)?;
            if !ring.params().is_feature_ext_arg() || !ring.params().is_feature_nodrop() {
                return Err(io::ErrorKind::Unsupported.into());
            }
            Ok(Self {
                ring,
                reads: ManuallyDrop::new(BTreeMap::new()),
            })
        }

        pub fn start(
            &mut self,
            id: i64,
            ticket: i64,
            path: String,
            limit: usize,
        ) -> Result<(), i32> {
            if self.reads.len() >= 64 {
                return Err(FAILED);
            }
            let read = Read {
                ticket,
                receiving: true,
                path: CString::new(path).map_err(|_| INVALID)?,
                bytes: vec![0; limit + 1],
                limit,
                phase: Phase::Opening,
            };
            let entry = opcode::OpenAt::new(types::Fd(libc::AT_FDCWD), read.path.as_ptr())
                .flags(libc::O_RDONLY | libc::O_CLOEXEC | libc::O_NONBLOCK)
                .build();
            self.reads.insert(id, read);
            self.push(id, entry);
            Ok(())
        }

        fn push(&mut self, id: i64, entry: squeue::Entry) {
            // At most 64 reads, each with exactly one queued or submitted
            // request, share 128 SQ entries. CString/Vec allocations remain
            // stable in reads until the corresponding CQE has been consumed.
            unsafe {
                self.ring
                    .submission()
                    .push(&entry.user_data(id as u64))
                    .expect("bounded read queue");
            }
        }

        pub fn cancel(&mut self, id: i64) {
            if let Some(read) = self.reads.get_mut(&id) {
                read.receiving = false;
            }
        }

        pub fn pending(&self) -> bool {
            !self.reads.is_empty()
        }

        pub fn collect(&mut self) -> io::Result<Vec<(i64, i64, Outcome)>> {
            self.ring.submit()?;
            let completed: Vec<_> = self
                .ring
                .completion()
                .map(|entry| (entry.user_data() as i64, entry.result()))
                .collect();
            let mut ready = Vec::new();
            for (id, answer) in completed {
                if let Some(result) = self.completed(id, answer) {
                    ready.push(result);
                }
            }
            Ok(ready)
        }

        fn completed(&mut self, id: i64, answer: i32) -> Option<(i64, i64, Outcome)> {
            let mut read = self
                .reads
                .remove(&id)
                .expect("completion belongs to a live read");
            match read.phase {
                Phase::Opening if answer < 0 => return read.deliver(id, Err(error(answer))),
                Phase::Opening => {
                    // A successful open CQE transfers exactly one descriptor.
                    let file = unsafe { OwnedFd::from_raw_fd(answer) };
                    if read.receiving {
                        self.read_more(id, read, file, 0);
                    } else {
                        self.close_file(id, read, file, Err(FAILED));
                    }
                }
                Phase::Reading { file, used } => {
                    // CQE ends the kernel's access to the buffer before we
                    // inspect, truncate, move or submit it again.
                    read.phase = Phase::Opening;
                    let count = used + answer.max(0) as usize;
                    if answer < 0 || !read.receiving {
                        self.close_file(id, read, file, Err(error(answer)));
                    } else if count > read.limit {
                        self.close_file(id, read, file, Err(TOO_LARGE));
                    } else if answer == 0 {
                        let mut bytes = std::mem::take(&mut read.bytes);
                        bytes.truncate(count);
                        self.close_file(id, read, file, Ok(bytes));
                    } else {
                        self.read_more(id, read, file, count);
                    }
                }
                Phase::Closing { result } => {
                    let ticket = read.ticket;
                    return read.receiving.then_some((
                        id,
                        ticket,
                        if answer < 0 {
                            Err(error(answer))
                        } else {
                            result
                        },
                    ));
                }
            }
            None
        }

        fn read_more(&mut self, id: i64, mut read: Read, file: OwnedFd, used: usize) {
            let entry = opcode::Read::new(
                types::Fd(file.as_raw_fd()),
                read.bytes[used..].as_mut_ptr(),
                (read.bytes.len() - used) as u32,
            )
            .offset(used as u64)
            .build();
            read.phase = Phase::Reading { file, used };
            self.reads.insert(id, read);
            self.push(id, entry);
        }

        fn close_file(&mut self, id: i64, mut read: Read, file: OwnedFd, result: Outcome) {
            let entry = opcode::Close::new(types::Fd(file.into_raw_fd())).build();
            read.phase = Phase::Closing { result };
            self.reads.insert(id, read);
            self.push(id, entry);
        }

        pub fn wait(&mut self, timeout: Option<Duration>) -> io::Result<()> {
            let result = match timeout {
                Some(duration) => {
                    let time = types::Timespec::from(duration);
                    self.ring
                        .submitter()
                        .submit_with_args(1, &types::SubmitArgs::new().timespec(&time))
                }
                None => self.ring.submit_and_wait(1),
            };
            match result {
                Err(error) if matches!(error.raw_os_error(), Some(libc::ETIME | libc::EINTR)) => {
                    Ok(())
                }
                other => other.map(|_| ()),
            }
        }

        pub fn close(&mut self) -> io::Result<()> {
            for read in self.reads.values_mut() {
                read.receiving = false;
            }
            while self.pending() {
                self.collect()?;
                if self.pending() {
                    self.wait(None)?;
                }
            }
            Ok(())
        }
    }

    impl Drop for Ring {
        fn drop(&mut self) {
            if self.close().is_ok() {
                // No queued/submitted request can refer to these allocations.
                unsafe {
                    ManuallyDrop::drop(&mut self.reads);
                }
            }
        }
    }

    impl Read {
        fn deliver(self, id: i64, result: Outcome) -> Option<(i64, i64, Outcome)> {
            self.receiving.then_some((id, self.ticket, result))
        }
    }

    fn error(answer: i32) -> i32 {
        match -answer {
            libc::ENOENT => NOT_FOUND,
            libc::EACCES | libc::EPERM => DENIED,
            _ => FAILED,
        }
    }

    // ---- Tests ----

    #[test]
    fn abandoned_requests_retain_capacity_until_their_kernel_work_ends() {
        let Ok(mut ring) = Ring::new() else {
            return;
        };
        let path = std::env::temp_dir().join(format!("snail-ring-capacity-{}", std::process::id()));
        std::fs::write(&path, b"data").unwrap();
        for id in 1..=64 {
            ring.start(id, id, path.to_str().unwrap().into(), 4)
                .unwrap();
            ring.cancel(id);
        }
        assert_eq!(
            ring.start(65, 65, path.to_str().unwrap().into(), 4),
            Err(FAILED)
        );
        ring.close().unwrap();
        assert!(ring.reads.is_empty());
        ring.start(66, 66, path.to_str().unwrap().into(), 4)
            .unwrap();
        ring.close().unwrap();
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn cancellation_during_read_and_close_drains_without_delivery() {
        let Ok(mut ring) = Ring::new() else {
            return;
        };
        let path = std::env::temp_dir().join(format!("snail-ring-cancel-{}", std::process::id()));
        std::fs::write(&path, b"contents").unwrap();
        for (id, closing) in [(1, false), (2, true)] {
            ring.start(id, 17, path.to_str().unwrap().into(), 8)
                .unwrap();
            loop {
                let phase = &ring.reads[&id].phase;
                if (!closing && matches!(phase, Phase::Reading { .. }))
                    || (closing && matches!(phase, Phase::Closing { .. }))
                {
                    break;
                }
                assert!(ring.collect().unwrap().is_empty());
                ring.wait(Some(Duration::from_secs(1))).unwrap();
            }
            ring.cancel(id);
            ring.close().unwrap();
            assert!(ring.reads.is_empty());
            assert!(ring.collect().unwrap().is_empty());
        }
        std::fs::remove_file(path).unwrap();
    }
}

// ---- Tests ----

#[cfg(all(test, target_os = "linux"))]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::Instant;

    static NEXT: AtomicUsize = AtomicUsize::new(0);

    fn directory() -> PathBuf {
        let path = std::env::temp_dir().join(format!(
            "snail-async-files-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir(&path).unwrap();
        path
    }

    fn supported() -> bool {
        match linux::Ring::new() {
            Ok(_) => true,
            Err(error) => {
                eprintln!("io_uring tests skipped: {error}");
                false
            }
        }
    }

    fn start(files: &mut Files, path: &std::path::Path, limit: i32) -> i64 {
        files.path = path.to_str().unwrap().into();
        files.start(17, limit).unwrap()
    }

    fn settle(files: &mut Files, id: i64) -> i32 {
        loop {
            let ready = files.collect().unwrap();
            if ready.contains(&(17, id)) {
                return files.finish(id).unwrap();
            }
            assert!(files.pending(), "request must own work until completion");
            files.wait(None).unwrap();
        }
    }

    #[test]
    fn reads_empty_exact_limit_oversized_and_missing_files() {
        if !supported() {
            return;
        }
        let directory = directory();
        let empty = directory.join("empty");
        let text = directory.join("λ.txt");
        std::fs::write(&empty, []).unwrap();
        std::fs::write(&text, b"hello").unwrap();
        let mut files = Files::default();
        for (path, limit, expected) in [
            (&empty, 0, 0),
            (&text, 5, 5),
            (&text, 4, TOO_LARGE),
            (&directory.join("absent"), 5, NOT_FOUND),
        ] {
            let id = start(&mut files, path, limit);
            assert_eq!(settle(&mut files, id), expected);
            if expected == 5 {
                assert_eq!(files.held, b"hello");
            }
        }
        assert!(!files.pending());
        std::fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn completed_result_is_consumed_or_canceled_once() {
        if !supported() {
            return;
        }
        let directory = directory();
        let path = directory.join("text");
        std::fs::write(&path, b"result").unwrap();
        let mut files = Files::default();
        let id = start(&mut files, &path, 6);
        while !files.collect().unwrap().contains(&(17, id)) {
            files.wait(None).unwrap();
        }
        files.cancel(id);
        assert!(files.finish(id).is_err());
        let next = start(&mut files, &path, 6);
        assert!(next > id);
        assert_eq!(settle(&mut files, next), 6);
        assert!(files.finish(next).is_err());
        std::fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn a_deadline_ends_a_completion_wait_without_polling() {
        if !supported() {
            return;
        }
        let mut ring = linux::Ring::new().unwrap();
        let started = Instant::now();
        ring.wait(Some(Duration::from_millis(15))).unwrap();
        assert!(started.elapsed() >= Duration::from_millis(10));
        assert!(ring.collect().unwrap().is_empty());
    }

    #[test]
    fn cancel_before_open_completion_keeps_resources_until_close() {
        if !supported() {
            return;
        }
        let directory = directory();
        let path = directory.join("text");
        std::fs::write(&path, b"discarded").unwrap();
        let mut files = Files::default();
        let id = start(&mut files, &path, 9);
        files.cancel(id);
        assert!(files.pending());
        files.close().unwrap();
        assert!(!files.pending());
        assert!(files.collect().unwrap().is_empty());
        assert!(files.finish(id).is_err());
        std::fs::remove_dir_all(directory).unwrap();
    }
}
