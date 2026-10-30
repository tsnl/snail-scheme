//! Path services for the Snail-Core library: the names a filesystem keeps,
//! where `io` serves the files behind them. Directories are made, listed and
//! removed, paths renamed and examined, and symbolic links made and read. A
//! file's whole text is read and written here too, as one value whose
//! failure a program can answer, where `io`'s ports fail the program.
//!
//! Each operation copies its staged path, resolves it as `io` does, and
//! answers at once with a scalar: a nonnegative result, or the negative code
//! of the `PathError` that stopped it. A failure a program can act on is a
//! value, not a trap. Staged text that is not Unicode is a bug in the caller
//! and takes `io`'s fatal path. No operation keeps a handle, so nothing here
//! takes part in cleanup.
//!
//! Rust's standard library reaches WASI preview1 for every operation, as it
//! does for `io`'s files: `path_create_directory`, `path_rename`,
//! `path_unlink_file`, `path_remove_directory`, `fd_readdir`,
//! `path_filestat_get`, `path_symlink` and `path_readlink`, and `path_open`,
//! `fd_filestat_get`, `fd_read` and `fd_write` for whole texts.

use crate::io::{checked, resolved, staged_path, staged_text};
use std::{
    cell::{Cell, RefCell},
    fs::{File, FileType, Metadata},
    io::{ErrorKind, Read},
    time::{SystemTime, UNIX_EPOCH},
};

// ---- Errors ----

/// Why a path operation failed, as Snail-Core's `FileError` names it. The
/// discriminants are the codes the operations answer, so the two enums agree
/// by number. What the runtime does not classify is `Other`, as is a host
/// with no filesystem, such as a page's.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i32)]
enum PathError {
    NotFound = -1,
    AlreadyExists = -2,
    NotEmpty = -3,
    NotADirectory = -4,
    IsADirectory = -5,
    PermissionDenied = -6,
    InvalidPath = -7,
    NotSupported = -8,
    Other = -9,
}

impl From<std::io::Error> for PathError {
    fn from(error: std::io::Error) -> Self {
        match error.kind() {
            ErrorKind::NotFound => Self::NotFound,
            ErrorKind::AlreadyExists => Self::AlreadyExists,
            ErrorKind::DirectoryNotEmpty => Self::NotEmpty,
            ErrorKind::NotADirectory => Self::NotADirectory,
            ErrorKind::IsADirectory => Self::IsADirectory,
            ErrorKind::PermissionDenied | ErrorKind::ReadOnlyFilesystem => Self::PermissionDenied,
            // A path with a NUL is refused before it reaches the host.
            ErrorKind::InvalidInput | ErrorKind::InvalidFilename => Self::InvalidPath,
            ErrorKind::Unsupported => Self::NotSupported,
            _ => uncategorized(&error),
        }
    }
}

// Rust's WASI target gives two errors no kind, so their WASI preview1
// numbers decide: ENOTEMPTY, and ENOTCAPABLE, a path outside every
// preopened directory. Another target numbers its errors differently.
const WASI_NOT_EMPTY: i32 = 55;
const WASI_NOT_CAPABLE: i32 = 76;

fn uncategorized(error: &std::io::Error) -> PathError {
    match error.raw_os_error() {
        Some(WASI_NOT_EMPTY) if cfg!(target_os = "wasi") => PathError::NotEmpty,
        Some(WASI_NOT_CAPABLE) if cfg!(target_os = "wasi") => PathError::PermissionDenied,
        _ => PathError::Other,
    }
}

/// The scalar an operation answers: its result, or its error's code.
fn answer(result: Result<i32, PathError>) -> i32 {
    result.unwrap_or_else(|error| error as i32)
}

fn done(result: std::io::Result<()>) -> i32 {
    answer(result.map(|()| 0).map_err(PathError::from))
}

// ---- Two paths ----

// Only one text can be staged before a call, so an operation on two paths
// takes them joined by NUL, which no path can hold. A program can still put
// a NUL in a path; then the split leaves one in the second part, which the
// filesystem never sees, because Rust refuses such a path as invalid.
fn split_pair(text: String) -> Result<(String, String), PathError> {
    text.split_once('\0')
        .map(|(first, second)| (first.to_string(), second.to_string()))
        .ok_or(PathError::InvalidPath)
}

fn staged_pair(count: u32) -> Result<(String, String), PathError> {
    split_pair(checked(staged_text(count)))
}

// ---- Directories and names ----

#[unsafe(export_name = "snail:io/make-directory")]
pub extern "C" fn make_directory(count: u32) -> i32 {
    done(std::fs::create_dir(checked(staged_path(count))))
}

/// Replaces what `to` names at once, as POSIX `rename` does: a reader sees
/// the old file or the new one, never neither.
#[unsafe(export_name = "snail:io/rename")]
pub extern "C" fn rename(count: u32) -> i32 {
    answer(staged_pair(count).and_then(|(from, to)| {
        std::fs::rename(resolved(from), resolved(to))?;
        Ok(0)
    }))
}

/// A file or a symbolic link; never a directory.
#[unsafe(export_name = "snail:io/remove-file")]
pub extern "C" fn remove_file(count: u32) -> i32 {
    done(std::fs::remove_file(checked(staged_path(count))))
}

/// An empty directory. Removing a tree is Snail-Core's, from listings.
#[unsafe(export_name = "snail:io/remove-directory")]
pub extern "C" fn remove_directory(count: u32) -> i32 {
    done(std::fs::remove_dir(checked(staged_path(count))))
}

// The names in a directory, without `.` and `..`, in scalar order, which is
// byte order: the host's own order differs from one filesystem to another.
// A name that is not UTF-8 cannot become a String, so it fails the listing.
fn names(path: &str) -> Result<Vec<String>, PathError> {
    let mut names = Vec::new();
    for entry in std::fs::read_dir(path)? {
        let name = entry?.file_name().into_string();
        names.push(name.map_err(|_| PathError::InvalidPath)?);
    }
    names.sort();
    Ok(names)
}

/// The names, joined by NUL, as the reply.
#[unsafe(export_name = "snail:io/list-directory")]
pub extern "C" fn list_directory(count: u32) -> i32 {
    let path = checked(staged_path(count));
    answer(names(&path).and_then(|names| reply(&names.join("\0"))))
}

// ---- Status ----

// `file-status` and `followed-status` answer a path's kind and leave its
// size and modification time here for the two reads that follow, as a reply
// is left: scratch owned by the runtime instance, replaced by the next
// status.
thread_local! {
    static STATUS: Cell<(i64, i64)> = const { Cell::new((0, 0)) };
}

/// A kind as `FileKind` numbers it. Only `file-status` sees a link as its
/// own kind; `followed-status` sees what the link names.
fn kind(file_type: FileType) -> i32 {
    if file_type.is_symlink() {
        2
    } else if file_type.is_dir() {
        1
    } else if file_type.is_file() {
        0
    } else {
        3
    }
}

/// Nanoseconds since the Unix epoch, negative before it.
fn nanoseconds(time: SystemTime) -> i64 {
    match time.duration_since(UNIX_EPOCH) {
        Ok(after) => i64::try_from(after.as_nanos()).unwrap_or(i64::MAX),
        Err(before) => i64::try_from(before.duration().as_nanos()).map_or(i64::MIN, |n| -n),
    }
}

fn recorded(metadata: Metadata) -> Result<i32, PathError> {
    let size = i64::try_from(metadata.len()).unwrap_or(i64::MAX);
    STATUS.set((size, nanoseconds(metadata.modified()?)));
    Ok(kind(metadata.file_type()))
}

/// The path itself, a link included (`path_filestat_get` without
/// `SYMLINK_FOLLOW`).
fn status(path: &str) -> Result<i32, PathError> {
    recorded(std::fs::symlink_metadata(path)?)
}

/// What opening the path finds, following each link to the file it names
/// (`path_filestat_get` with `SYMLINK_FOLLOW`). A link to nothing is
/// `NotFound`, though `status` finds the link.
fn followed(path: &str) -> Result<i32, PathError> {
    recorded(std::fs::metadata(path)?)
}

#[unsafe(export_name = "snail:io/file-status")]
pub extern "C" fn file_status(count: u32) -> i32 {
    answer(status(&checked(staged_path(count))))
}

#[unsafe(export_name = "snail:io/followed-status")]
pub extern "C" fn followed_status(count: u32) -> i32 {
    answer(followed(&checked(staged_path(count))))
}

#[unsafe(export_name = "snail:io/status-size")]
pub extern "C" fn status_size() -> i64 {
    STATUS.get().0
}

#[unsafe(export_name = "snail:io/status-modified")]
pub extern "C" fn status_modified() -> i64 {
    STATUS.get().1
}

// ---- Symbolic links ----

// The target is the link's text, kept as given: a relative target is read
// from the link's own directory, so only the link's path is resolved.
// `soft_link` is the standard library's one portable spelling; the WASI
// `symlink_path` is still unstable.
fn make_link(target: String, path: String) -> Result<i32, PathError> {
    #[allow(deprecated)]
    std::fs::soft_link(target, resolved(path))?;
    Ok(0)
}

/// Joined as target, NUL, path, in `ln -s` order.
#[unsafe(export_name = "snail:io/make-symbolic-link")]
pub extern "C" fn make_symbolic_link(count: u32) -> i32 {
    answer(staged_pair(count).and_then(|(target, path)| make_link(target, path)))
}

fn link_target(path: &str) -> Result<i32, PathError> {
    let target = std::fs::read_link(path)?.into_os_string().into_string();
    reply(&target.map_err(|_| PathError::InvalidPath)?)
}

/// The target, as the reply.
#[unsafe(export_name = "snail:io/read-symbolic-link")]
pub extern "C" fn read_symbolic_link(count: u32) -> i32 {
    answer(link_target(&checked(staged_path(count))))
}

// ---- Whole texts ----

// A service that reads and saves files for an editor answers each failure,
// so these take a file's text as one value and fail with a code. Reading
// refuses, besides a `PathError`, what is not one version of a text file;
// Snail-Core's `TextError` numbers these after `FileError`'s.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i32)]
enum Refusal {
    NotRegularFile = -10,
    TooLong = -11,
    NotText = -12,
    Changed = -13,
}

#[derive(Debug, PartialEq, Eq)]
enum TextError {
    Path(PathError),
    Refused(Refusal),
}

impl From<std::io::Error> for TextError {
    fn from(error: std::io::Error) -> Self {
        Self::Path(error.into())
    }
}

impl TextError {
    fn code(self) -> i32 {
        match self {
            Self::Path(error) => error as i32,
            Self::Refused(refusal) => refusal as i32,
        }
    }
}

/// The text of the regular file at `path`, of at most `limit` bytes. The
/// path itself must be the file: a link is not followed, and a FIFO, which
/// would wait for a writer, is not opened. The text is one version of the
/// file: it kept its length and modification time while it was read, and
/// the read found that length. A writer that keeps both can still race it.
fn file_text(path: &str, limit: u64) -> Result<String, TextError> {
    if !std::fs::symlink_metadata(path)?.is_file() {
        return Err(TextError::Refused(Refusal::NotRegularFile));
    }
    let mut file = File::open(path)?;
    let before = file.metadata()?;
    if before.len() > limit {
        return Err(TextError::Refused(Refusal::TooLong));
    }
    let mut bytes = Vec::new();
    (&mut file).take(limit + 1).read_to_end(&mut bytes)?;
    if !one_version(&before, &file.metadata()?, bytes.len()) {
        return Err(TextError::Refused(Refusal::Changed));
    }
    String::from_utf8(bytes).map_err(|_| TextError::Refused(Refusal::NotText))
}

fn one_version(before: &Metadata, after: &Metadata, read: usize) -> bool {
    before.len() == after.len()
        && u64::try_from(read) == Ok(after.len())
        && before.modified().ok() == after.modified().ok()
}

/// The text, as the reply. A negative limit is no bytes.
#[unsafe(export_name = "snail:io/read-text")]
pub extern "C" fn read_text(limit: i64, count: u32) -> i32 {
    let path = checked(staged_path(count));
    match file_text(&path, u64::try_from(limit).unwrap_or(0)) {
        Ok(text) => answer(reply(&text)),
        Err(error) => error.code(),
    }
}

fn write_whole(path: String, text: String) -> Result<i32, PathError> {
    std::fs::write(resolved(path), text)?;
    Ok(0)
}

/// Joined as path, NUL, text, so the text is everything after the first
/// NUL. The file is made, or replaced in place.
#[unsafe(export_name = "snail:io/write-text")]
pub extern "C" fn write_text(count: u32) -> i32 {
    answer(staged_pair(count).and_then(|(path, text)| write_whole(path, text)))
}

// ---- Replies ----

// An operation that finds text, a directory's names or a link's target,
// leaves it here as scalars and answers their count; Snail-Core reads them
// one at a time before it performs another path operation. Like `datum`'s
// real text, the reply is scratch owned by the runtime instance, with no
// handle and no cleanup, and the next reply replaces it.
thread_local! {
    static REPLY: RefCell<Vec<char>> = const { RefCell::new(Vec::new()) };
}

fn reply(text: &str) -> Result<i32, PathError> {
    let scalars: Vec<char> = text.chars().collect();
    let count = i32::try_from(scalars.len()).map_err(|_| PathError::Other)?;
    REPLY.set(scalars);
    Ok(count)
}

#[unsafe(export_name = "snail:io/reply-character")]
pub extern "C" fn reply_character(index: u32) -> u32 {
    let character = REPLY.with_borrow(|reply| reply.get(index as usize).copied());
    let found = character.ok_or_else(|| "no reply character at that index".to_string());
    u32::from(checked(found))
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    // A fresh directory of this test's own, so tests may run in parallel.
    fn scratch(name: &str) -> PathBuf {
        let directory =
            std::env::temp_dir().join(format!("snail-paths-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&directory);
        std::fs::create_dir(&directory).unwrap();
        directory
    }

    fn text(path: &std::path::Path) -> String {
        path.to_str().unwrap().to_string()
    }

    fn reply_text() -> String {
        REPLY.with_borrow(|reply| reply.iter().collect())
    }

    #[test]
    fn pairs_split_at_the_first_nul_only() {
        assert_eq!(split_pair("a\0b".into()), Ok(("a".into(), "b".into())));
        assert_eq!(
            split_pair("a\0b\0c".into()),
            Ok(("a".into(), "b\0c".into()))
        );
        assert_eq!(split_pair("a".into()), Err(PathError::InvalidPath));
        let directory = scratch("nul");
        let from = text(&directory.join("from"));
        std::fs::write(&from, "x").unwrap();
        let rename = |to: String| std::fs::rename(&from, to).map_err(PathError::from);
        assert_eq!(rename(format!("{from}\0more")), Err(PathError::InvalidPath));
        std::fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn listings_are_sorted_and_failures_are_classified() {
        let directory = scratch("list");
        for name in ["b", "λ", "a", "B"] {
            std::fs::write(directory.join(name), name).unwrap();
        }
        std::fs::create_dir(directory.join("sub")).unwrap();
        let count = names(&text(&directory)).and_then(|names| reply(&names.join("\0")));
        assert_eq!(count, Ok(11));
        assert_eq!(reply_text(), "B\0a\0b\0sub\0λ");
        assert_eq!(
            names(&text(&directory.join("missing"))),
            Err(PathError::NotFound)
        );
        assert_eq!(
            names(&text(&directory.join("a"))),
            Err(PathError::NotADirectory)
        );
        let removed = std::fs::remove_dir(&directory).map_err(PathError::from);
        assert_eq!(removed, Err(PathError::NotEmpty));
        let made = std::fs::create_dir(directory.join("sub")).map_err(PathError::from);
        assert_eq!(made, Err(PathError::AlreadyExists));
        std::fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn status_does_not_follow_links() {
        let directory = scratch("status");
        let file = directory.join("file");
        std::fs::write(&file, "four").unwrap();
        assert_eq!(status(&text(&file)), Ok(0));
        assert_eq!(status_size(), 4);
        assert!(status_modified() > 0);
        assert_eq!(status(&text(&directory)), Ok(1));
        assert_eq!(
            make_link("file".into(), text(&directory.join("link"))),
            Ok(0)
        );
        assert_eq!(status(&text(&directory.join("link"))), Ok(2));
        assert_eq!(link_target(&text(&directory.join("link"))), Ok(4));
        assert_eq!(reply_text(), "file");
        assert_eq!(link_target(&text(&file)), Err(PathError::InvalidPath));
        assert_eq!(
            status(&text(&directory.join("missing"))),
            Err(PathError::NotFound)
        );
        std::fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn followed_status_sees_what_a_link_names() {
        let directory = scratch("followed");
        std::fs::write(directory.join("file"), "four").unwrap();
        let link = |target: &str, name: &str| make_link(target.into(), text(&directory.join(name)));
        assert_eq!(link("file", "link"), Ok(0));
        assert_eq!(link("link", "chain"), Ok(0));
        assert_eq!(link(".", "here"), Ok(0));
        assert_eq!(link("missing", "dangling"), Ok(0));
        assert_eq!(followed(&text(&directory.join("chain"))), Ok(0));
        assert_eq!(status_size(), 4);
        assert_eq!(followed(&text(&directory.join("here"))), Ok(1));
        let dangling = text(&directory.join("dangling"));
        assert_eq!(followed(&dangling), Err(PathError::NotFound));
        assert_eq!(status(&dangling), Ok(2));
        std::fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn texts_are_one_version_of_a_regular_file() {
        let directory = scratch("text");
        let file = text_path(&directory, "file");
        std::fs::write(&file, "λ text").unwrap();
        assert_eq!(file_text(&file, 7), Ok("λ text".into()));
        assert_eq!(
            file_text(&file, 6),
            Err(TextError::Refused(Refusal::TooLong))
        );
        assert_eq!(
            file_text(&file, 0),
            Err(TextError::Refused(Refusal::TooLong))
        );
        std::fs::write(&file, [0xff, 0x41]).unwrap();
        assert_eq!(
            file_text(&file, 8),
            Err(TextError::Refused(Refusal::NotText))
        );
        assert_eq!(
            make_link("file".into(), text_path(&directory, "link")),
            Ok(0)
        );
        let refused = Err(TextError::Refused(Refusal::NotRegularFile));
        assert_eq!(file_text(&text_path(&directory, "link"), 8), refused);
        assert_eq!(file_text(&text(&directory), 8), refused);
        let missing = file_text(&text_path(&directory, "missing"), 8);
        assert_eq!(missing, Err(TextError::Path(PathError::NotFound)));
        assert_eq!(TextError::Refused(Refusal::Changed).code(), -13);
        let written = text_path(&directory, "written");
        assert_eq!(write_whole(written.clone(), "a\0b".into()), Ok(0));
        assert_eq!(std::fs::read_to_string(&written).unwrap(), "a\0b");
        std::fs::remove_dir_all(directory).unwrap();
    }

    fn text_path(directory: &std::path::Path, name: &str) -> String {
        text(&directory.join(name))
    }

    #[test]
    fn times_before_the_epoch_are_negative() {
        let second = std::time::Duration::from_secs(1);
        assert_eq!(nanoseconds(UNIX_EPOCH + second), 1_000_000_000);
        assert_eq!(nanoseconds(UNIX_EPOCH - second), -1_000_000_000);
        assert_eq!(answer(Err(PathError::Other)), -9);
        assert_eq!(answer(Ok(3)), 3);
    }
}
