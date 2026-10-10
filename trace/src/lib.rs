//! Always-on Chromium trace events. Each process owns one file; recording never
//! allocates Scheme objects or triggers collection. Only coarse operations are
//! traced. A completed write leaves valid JSON, even before the process exits.

use std::{
    fs::{self, File, OpenOptions},
    io::{self, Seek, SeekFrom, Write},
    marker::PhantomData,
    path::PathBuf,
    rc::Rc,
    sync::{
        Mutex, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
    time::{Instant, SystemTime, UNIX_EPOCH},
};

// ---- Scoped events ----

static RECORDER: OnceLock<Mutex<Option<Recorder>>> = OnceLock::new();
static NEXT_THREAD: AtomicU64 = AtomicU64::new(1);
thread_local! { static THREAD: u64 = NEXT_THREAD.fetch_add(1, Ordering::Relaxed); }

/// A span must end on the thread where it began. Explicit process exit and
/// abort bypass Drop and leave an unfinished begin event in the trace.
pub struct Span {
    started: Instant,
    same_thread: PhantomData<Rc<()>>,
}

pub fn span(name: &str) -> Span {
    begin(name);
    Span {
        started: Instant::now(),
        same_thread: PhantomData,
    }
}

impl Span {
    pub fn elapsed(&self) -> std::time::Duration {
        self.started.elapsed()
    }
}

impl Drop for Span {
    fn drop(&mut self) {
        end();
    }
}

/// Low-level boundary used by the Scheme tracing adapter.
pub fn begin(name: &str) {
    record(name, 'B');
}

pub fn end() {
    record("", 'E');
}

/// Resolve before launching children whose working directories may differ.
pub fn directory() -> io::Result<PathBuf> {
    let path = std::env::var_os("SNAIL_TRACE_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("build/traces"));
    Ok(std::env::current_dir()?.join(path))
}

fn record(name: &str, phase: char) {
    let recorder = RECORDER.get_or_init(|| Mutex::new(open_recorder()));
    let Ok(mut recorder) = recorder.lock() else {
        return;
    };
    if let Some(writer) = recorder.as_mut()
        && let Err(error) = writer.event(name, phase, THREAD.with(|id| *id))
    {
        let _ = writeln!(io::stderr(), "snail-trace: {error}");
        *recorder = None;
    }
}

fn open_recorder() -> Option<Recorder> {
    let result = match std::env::var("SNAIL_TRACE_OPEN_ERROR") {
        Ok(error) => Err(io::Error::other(error)),
        Err(_) => directory().and_then(Recorder::open),
    };
    match result {
        Ok(recorder) => Some(recorder),
        Err(error) => {
            let _ = writeln!(io::stderr(), "snail-trace: {error}");
            None
        }
    }
}

// ---- File format ----

struct Recorder {
    file: File,
    started: Instant,
    first: bool,
}

impl Recorder {
    fn open(directory: PathBuf) -> io::Result<Self> {
        fs::create_dir_all(&directory)?;
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        for serial in 0_u64.. {
            let path = directory.join(format!("rust-{}-{stamp}-{serial}.json", process_id()));
            match OpenOptions::new().write(true).create_new(true).open(path) {
                Ok(file) => return Self::new(file),
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error),
            }
        }
        unreachable!()
    }

    fn new(mut file: File) -> io::Result<Self> {
        file.write_all(b"[]")?;
        Ok(Self {
            file,
            started: Instant::now(),
            first: true,
        })
    }

    // Hold the recorder lock across the entire seek/write operation. Seeking
    // from the end uses bytes, independent of Unicode label lengths.
    fn event(&mut self, name: &str, phase: char, thread: u64) -> io::Result<()> {
        let separator = if self.first { "" } else { ",\n" };
        let event = format!(
            "{separator}{{\"name\":{},\"cat\":\"snail\",\"ph\":\"{phase}\",\"ts\":{},\"pid\":{},\"tid\":{thread}}}]",
            json_string(name),
            self.started.elapsed().as_micros(),
            process_id()
        );
        self.file.seek(SeekFrom::End(-1))?;
        self.file.write_all(event.as_bytes())?;
        self.file.flush()?;
        self.first = false;
        Ok(())
    }
}

fn process_id() -> u32 {
    #[cfg(target_os = "wasi")]
    {
        0
    } // WASI preview 1 has no process IDs; exclusive filenames disambiguate.
    #[cfg(not(target_os = "wasi"))]
    {
        std::process::id()
    }
}

fn json_string(text: &str) -> String {
    let mut result = String::from("\"");
    for character in text.chars() {
        match character {
            '"' => result.push_str("\\\""),
            '\\' => result.push_str("\\\\"),
            c if c.is_control() => result.push_str(&format!("\\u{:04x}", c as u32)),
            c => result.push(c),
        }
    }
    result.push('"');
    result
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escapes_json_without_losing_unicode() {
        assert_eq!(json_string("a\"\\\n\tλ"), "\"a\\\"\\\\\\u000a\\u0009λ\"");
    }

    #[test]
    fn exclusive_creation_preserves_previous_traces() {
        let directory = std::env::temp_dir().join(format!("snail-trace-test-{}", process_id()));
        fs::create_dir_all(&directory).unwrap();
        let before = fs::read_dir(&directory).unwrap().count();
        let mut a = Recorder::open(directory.clone()).unwrap();
        let _b = Recorder::open(directory.clone()).unwrap();
        assert_eq!(fs::read_dir(&directory).unwrap().count(), before + 2);
        a.event("λ\n", 'B', 1).unwrap();
        a.event("", 'E', 1).unwrap();
        let files: Vec<_> = fs::read_dir(&directory)
            .unwrap()
            .map(|entry| fs::read_to_string(entry.unwrap().path()).unwrap())
            .collect();
        assert!(files.iter().any(|text| text == "[]"));
        assert!(
            files
                .iter()
                .any(|text| text.starts_with("[{\"name\":\"λ\\u000a\"")
                    && text.ends_with("}]")
                    && text.matches("\"ph\"").count() == 2)
        );
        drop((a, _b));
        fs::remove_dir_all(directory).unwrap();
    }
}
