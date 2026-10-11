//! Native build effects. Each operation is a named AWI call into this runtime.
//! Build directories are registered only to report retained work on a terminal
//! error. The registry is not a rollback stack, and does not run Scheme cleanup.

use crate::{arguments, awi::Root, finish, string_text};
use std::os::unix::{
    fs::{DirBuilderExt, MetadataExt, symlink},
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

#[unsafe(export_name = "snail:%copy-file")]
pub extern "C" fn copy_file(raw: u32) -> u32 {
    let args = arguments(raw, "copy-file", 2, 2);
    finish((|| {
        let source = PathBuf::from(string_text(&args.get(0)?)?);
        let output = PathBuf::from(string_text(&args.get(1)?)?);
        if !source.is_file() {
            return Err(format!(
                "artifact is not a regular file: {}",
                source.display()
            ));
        }
        fs::copy(&source, &output)
            .map_err(|error| format!("cannot copy artifact {}: {error}", source.display()))?;
        Ok(Root::unspecified())
    })())
}

// A relative public link selects one completed generation. Keep old generations
// for already-running processes; current_exe resolves to their actual payload.
fn publish_bundle(bundle: &Path, output: &Path) -> io::Result<()> {
    let output = std::path::absolute(output)?;
    let destination = reserve_named_directory(
        output
            .parent()
            .ok_or_else(|| io::Error::other("output has no parent"))?,
        ".snail-artifacts-",
    )?;
    if let Err(error) = fs::rename(bundle, &destination) {
        let _ = fs::remove_dir(&destination);
        return Err(error);
    }
    let link = bundle
        .parent()
        .ok_or_else(|| io::Error::other("bundle has no parent"))?
        .join("publish");
    let publish = || {
        symlink(
            Path::new(destination.file_name().unwrap()).join("program"),
            &link,
        )?;
        fs::rename(&link, output)
    };
    if let Err(error) = publish() {
        if let Err(restore) = fs::rename(&destination, bundle) {
            eprintln!(
                "artifact generation retained: {}: {restore}",
                destination.display()
            );
        }
        return Err(error);
    }
    Ok(())
}

#[unsafe(export_name = "snail:%publish-bundle")]
pub extern "C" fn publish_artifact_bundle(raw: u32) -> u32 {
    let args = arguments(raw, "publish-bundle", 2, 2);
    finish((|| {
        let bundle = string_text(&args.get(0)?)?;
        let output = string_text(&args.get(1)?)?;
        publish_bundle(Path::new(&bundle), Path::new(&output))
            .map_err(|error| format!("cannot publish artifact bundle {output}: {error}"))?;
        Ok(Root::unspecified())
    })())
}

// ---- Private staging directories ----

thread_local! { static DIRECTORIES: RefCell<Vec<PathBuf>> = const { RefCell::new(Vec::new()) }; }

// Returning a reserved directory establishes ownership before path conversion
// or allocation of its Scheme wrapper can fail.
fn reserve_directory(parent: &Path) -> io::Result<PathBuf> {
    let path = reserve_named_directory(parent, ".snail-build-")?;
    DIRECTORIES.with_borrow_mut(|paths| paths.push(path.clone()));
    Ok(path)
}

fn reserve_named_directory(parent: &Path, prefix: &str) -> io::Result<PathBuf> {
    fs::create_dir_all(parent)?;
    for serial in 0..1024 {
        let path = parent.join(format!("{prefix}{}-{serial}", std::process::id()));
        match fs::DirBuilder::new().mode(0o700).create(&path) {
            Ok(()) => return Ok(path),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error),
        }
    }
    Err(io::Error::other("cannot reserve build directory"))
}

// Consume ownership before removal. Cleanup failure warns but cannot change a
// successful build or make a later error report this directory as unfinished.
fn clean_directory(path: &Path) -> Result<(), String> {
    let owned = DIRECTORIES.with_borrow_mut(|paths| {
        paths
            .iter()
            .position(|owned| owned == path)
            .map(|index| paths.remove(index))
    });
    let owned = owned.ok_or("build directory is not owned by this invocation")?;
    if let Err(error) = fs::remove_dir_all(&owned) {
        eprintln!(
            "could not remove build directory: {}: {error}",
            owned.display()
        );
    }
    Ok(())
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
        Ok(Root::string(&path_text(path)?))
    })())
}

#[unsafe(export_name = "snail:%clean-build-directory")]
pub extern "C" fn clean_build_directory(raw: u32) -> u32 {
    let args = arguments(raw, "clean-build-directory", 1, 1);
    finish((|| {
        let path = PathBuf::from(string_text(&args.get(0)?)?);
        clean_directory(&path)?;
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
        clean_directory(&directory).unwrap();
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
        clean_directory(&first).unwrap();
        clean_directory(&second).unwrap();
        clean_directory(&parent).unwrap();
    }

    #[test]
    fn cleanup_requires_and_consumes_ownership() {
        let parent = reserve_directory(&std::env::temp_dir()).unwrap();
        let unowned = parent.join("unowned");
        fs::create_dir(&unowned).unwrap();
        assert!(clean_directory(&unowned).is_err());
        assert!(unowned.is_dir());
        clean_directory(&parent).unwrap();
        assert!(!parent.exists());
        assert!(clean_directory(&parent).is_err());
    }

    #[test]
    fn failed_removal_still_consumes_ownership() {
        // Keep the parent reserved while replacing the child. Other parallel
        // tests must not reuse the temporarily absent directory name.
        let parent = reserve_directory(&std::env::temp_dir()).unwrap();
        let directory = reserve_directory(&parent).unwrap();
        fs::remove_dir(&directory).unwrap();
        fs::write(&directory, "a file prevents recursive directory removal").unwrap();
        clean_directory(&directory).unwrap();
        assert!(directory.is_file());
        assert!(clean_directory(&directory).is_err());
        fs::remove_file(directory).unwrap();
        clean_directory(&parent).unwrap();
    }

    #[test]
    fn publication_selects_a_complete_generation_and_retains_the_old_one() {
        let parent = reserve_directory(&std::env::temp_dir()).unwrap();
        let output = parent.join("application");
        let mut generations = Vec::new();
        for value in ["first", "second"] {
            let workspace = reserve_directory(&parent).unwrap();
            let bundle = workspace.join("bundle");
            fs::create_dir_all(bundle.join("artifacts")).unwrap();
            fs::write(bundle.join("program"), value).unwrap();
            fs::write(bundle.join("artifacts/data"), value).unwrap();
            publish_bundle(&bundle, &output).unwrap();
            clean_directory(&workspace).unwrap();
            let payload = output.canonicalize().unwrap();
            assert_eq!(fs::read_to_string(&payload).unwrap(), value);
            assert_eq!(
                fs::read_to_string(payload.parent().unwrap().join("artifacts/data")).unwrap(),
                value
            );
            generations.push(payload);
        }
        assert_ne!(generations[0], generations[1]);
        assert_eq!(fs::read_to_string(&generations[0]).unwrap(), "first");
        assert!(!fs::read_link(output).unwrap().is_absolute());
        clean_directory(&parent).unwrap();
    }

    #[test]
    fn failed_publication_restores_the_candidate_and_preserves_the_destination() {
        let parent = reserve_directory(&std::env::temp_dir()).unwrap();
        let workspace = reserve_directory(&parent).unwrap();
        let bundle = workspace.join("bundle");
        let output = parent.join("blocked");
        fs::create_dir(&bundle).unwrap();
        fs::write(bundle.join("program"), "candidate").unwrap();
        fs::create_dir(&output).unwrap();
        fs::write(output.join("keep"), "previous").unwrap();
        assert!(publish_bundle(&bundle, &output).is_err());
        assert_eq!(
            fs::read_to_string(bundle.join("program")).unwrap(),
            "candidate"
        );
        assert_eq!(fs::read_to_string(output.join("keep")).unwrap(), "previous");
        assert!(!fs::read_dir(&parent).unwrap().any(|entry| {
            entry
                .unwrap()
                .file_name()
                .to_string_lossy()
                .starts_with(".snail-artifacts-")
        }));
        clean_directory(&workspace).unwrap();
        clean_directory(&parent).unwrap();
    }
}
