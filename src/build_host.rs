//! Native build effects. Each operation is a named AWI call into this runtime.
//! Build directories are registered only to report retained work on a terminal
//! error. The registry is not a rollback stack, and does not run Scheme cleanup.

use crate::{arguments, awi::Root, finish, string_text};
use std::os::unix::{
    fs::{DirBuilderExt, MetadataExt},
    process::{CommandExt, ExitStatusExt},
};
use std::{
    cell::RefCell,
    fs, io,
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

// ---- Literal subprocess invocation ----

fn strings(mut value: Root) -> Result<Vec<String>, String> {
    let mut result = Vec::new();
    while value.kind() != crate::awi::Kind::Nil {
        result.push(string_text(&value.car()?)?);
        value = value.cdr()?;
    }
    Ok(result)
}

fn process_status(argv: &[String], cwd: &str, input: bool, identity: &str) -> io::Result<i32> {
    let (program, args) = argv
        .split_first()
        .ok_or_else(|| io::Error::other("empty command"))?;
    let mut command = Command::new(program);
    command.args(args).arg0(identity).current_dir(cwd);
    command.stdin(if input {
        Stdio::inherit()
    } else {
        Stdio::null()
    });
    let status = command.status()?;
    Ok(status
        .code()
        .unwrap_or_else(|| 128 + status.signal().unwrap_or(0)))
}

#[unsafe(export_name = "snail:%process-status")]
pub extern "C" fn run_process(raw: u32) -> u32 {
    let args = arguments(raw, "process-status", 4, 4);
    finish((|| {
        let argv = strings(args.get(0)?)?;
        let cwd = string_text(&args.get(1)?)?;
        let input = args.get(2)?.as_bool()?;
        let identity = string_text(&args.get(3)?)?;
        process_status(&argv, &cwd, input, &identity)
            .map(|code| Root::integer(code.into()))
            .map_err(|error| format!("cannot run {argv:?}: {error}"))
    })())
}

// ---- Paths and atomic publication ----

#[unsafe(export_name = "snail:%create-directory*")]
pub extern "C" fn create_directory(raw: u32) -> u32 {
    let args = arguments(raw, "create-directory*", 1, 1);
    finish((|| {
        let path = string_text(&args.get(0)?)?;
        fs::create_dir_all(&path)
            .map_err(|error| format!("cannot create directory {path}: {error}"))?;
        Ok(Root::unspecified())
    })())
}

fn path_text(path: PathBuf) -> Result<String, String> {
    path.into_os_string()
        .into_string()
        .map_err(|_| "path is not UTF-8".into())
}

#[unsafe(export_name = "snail:%absolute-path")]
pub extern "C" fn absolute_path(raw: u32) -> u32 {
    let args = arguments(raw, "absolute-path", 1, 1);
    finish((|| {
        let path = string_text(&args.get(0)?)?;
        let absolute = std::path::absolute(path).map_err(|error| error.to_string())?;
        Ok(Root::string(&path_text(absolute)?))
    })())
}

fn same_file(first: &Path, second: &Path) -> io::Result<bool> {
    let metadata = |path| match fs::metadata(path) {
        Ok(value) => Ok(Some(value)),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error),
    };
    Ok(match (metadata(first)?, metadata(second)?) {
        (Some(a), Some(b)) => a.dev() == b.dev() && a.ino() == b.ino(),
        _ => false,
    })
}

#[unsafe(export_name = "snail:%same-file?")]
pub extern "C" fn same_file_call(raw: u32) -> u32 {
    let args = arguments(raw, "same-file?", 2, 2);
    finish((|| {
        let first = string_text(&args.get(0)?)?;
        let second = string_text(&args.get(1)?)?;
        same_file(Path::new(&first), Path::new(&second))
            .map(Root::boolean)
            .map_err(|error| error.to_string())
    })())
}

#[unsafe(export_name = "snail:%publish-file")]
pub extern "C" fn publish_file(raw: u32) -> u32 {
    let args = arguments(raw, "publish-file", 2, 2);
    finish((|| {
        let source = string_text(&args.get(0)?)?;
        let output = string_text(&args.get(1)?)?;
        fs::rename(&source, &output)
            .map_err(|error| format!("cannot publish {output}: {error}"))?;
        Ok(Root::unspecified())
    })())
}

// ---- Private staging directories ----

thread_local! { static DIRECTORIES: RefCell<Vec<PathBuf>> = const { RefCell::new(Vec::new()) }; }

fn reserve_directory(parent: &Path) -> io::Result<PathBuf> {
    fs::create_dir_all(parent)?;
    for serial in 0..1024 {
        let path = parent.join(format!(".snail-build-{}-{serial}", std::process::id()));
        match fs::DirBuilder::new().mode(0o700).create(&path) {
            Ok(()) => return Ok(path),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error),
        }
    }
    Err(io::Error::other("cannot reserve build directory"))
}

#[unsafe(export_name = "snail:%reserve-build-directory")]
pub extern "C" fn reserve_build_directory(raw: u32) -> u32 {
    let args = arguments(raw, "reserve-build-directory", 1, 1);
    finish((|| {
        let output = args.get(0)?;
        let parent = if output.kind() == crate::awi::Kind::Boolean && !output.as_bool()? {
            std::env::temp_dir()
        } else {
            let path =
                std::path::absolute(string_text(&output)?).map_err(|error| error.to_string())?;
            path.parent()
                .ok_or("output has no parent directory")?
                .to_owned()
        };
        let path = reserve_directory(&parent).map_err(|error| error.to_string())?;
        DIRECTORIES.with_borrow_mut(|paths| paths.push(path.clone()));
        Ok(Root::string(&path_text(path)?))
    })())
}

// Successful publication stays successful even if removal fails. Forget the
// registration after warning, so a later unrelated error cannot mislabel it.
#[unsafe(export_name = "snail:%clean-build-directory")]
pub extern "C" fn clean_build_directory(raw: u32) -> u32 {
    let args = arguments(raw, "clean-build-directory", 1, 1);
    finish((|| {
        let path = PathBuf::from(string_text(&args.get(0)?)?);
        let owned = DIRECTORIES.with_borrow_mut(|paths| {
            paths
                .iter()
                .position(|p| *p == path)
                .map(|index| paths.remove(index))
        });
        let owned = owned.ok_or("build directory is not owned by this invocation")?;
        if let Err(error) = fs::remove_dir_all(&owned) {
            eprintln!(
                "could not remove build directory: {}: {error}",
                owned.display()
            );
        }
        Ok(Root::unspecified())
    })())
}

pub fn report_retained_directories() {
    DIRECTORIES.with_borrow(|paths| {
        for path in paths {
            eprintln!("build failed; intermediates retained: {}", path.display());
        }
    });
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn commands_preserve_arguments_directory_and_status() {
        let directory = reserve_directory(&std::env::temp_dir()).unwrap();
        let output = directory.join("args");
        let args = [
            "sh",
            "-c",
            "printf '%s\\n' \"$0\" \"$@\" > args; exit 7",
            "ignored",
            "",
            "a b",
            "$(literal)",
        ]
        .map(str::to_owned);
        assert_eq!(
            process_status(&args, directory.to_str().unwrap(), false, "identity").unwrap(),
            7
        );
        assert_eq!(
            fs::read_to_string(output).unwrap(),
            "ignored\n\na b\n$(literal)\n"
        );
        let signal = ["sh", "-c", "kill -TERM $$"].map(str::to_owned);
        assert_eq!(process_status(&signal, ".", false, "sh").unwrap(), 143);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn build_tools_see_eof_and_missing_commands_are_errors() {
        let args = ["sh", "-c", "read line && exit 2; exit 0"].map(str::to_owned);
        assert_eq!(process_status(&args, ".", false, "sh").unwrap(), 0);
        assert!(
            process_status(&["/nonexistent/snail-test-command".into()], ".", false, "x").is_err()
        );
    }

    #[test]
    fn directories_are_private_and_aliases_compare_by_identity() {
        use std::os::unix::fs::{PermissionsExt, symlink};
        let parent = reserve_directory(&std::env::temp_dir()).unwrap();
        let first = reserve_directory(&parent).unwrap();
        let second = reserve_directory(&parent).unwrap();
        assert_ne!(first, second);
        assert_eq!(
            fs::metadata(&first).unwrap().permissions().mode() & 0o777,
            0o700
        );
        let source = parent.join("source");
        fs::write(&source, "keep").unwrap();
        let alias = parent.join("alias");
        symlink(&source, &alias).unwrap();
        assert!(same_file(&source, &alias).unwrap());
        fs::remove_file(&alias).unwrap();
        fs::hard_link(&source, &alias).unwrap();
        assert!(same_file(&source, &alias).unwrap());
        assert!(!same_file(&source, &parent.join("missing")).unwrap());
        fs::remove_dir_all(parent).unwrap();
    }
}
