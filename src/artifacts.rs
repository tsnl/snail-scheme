//! Companion files belong to a published generation. The Wasm loader supplies
//! its artifact directory; native programs use their physical executable path.

use crate::{abi::Root, arguments, finish, string_text};
use std::{io, path::PathBuf};

// ---- Installed artifact lookup ----

fn valid_name(name: &str) -> bool {
    !name.is_empty() && name != "." && name != ".." && !name.contains(['/', '\\', '\0'])
}

fn find_in(root: PathBuf, name: &str) -> Result<Option<PathBuf>, String> {
    if !valid_name(name) {
        return Err(format!("artifact name must be a filename: {name:?}"));
    }
    let path = root.join(name);
    match path.metadata() {
        Ok(metadata) if metadata.is_file() => Ok(Some(path)),
        Ok(_) => Err(format!(
            "artifact is not a regular file: {}",
            path.display()
        )),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(format!(
            "cannot access artifact {}: {error}",
            path.display()
        )),
    }
}

fn find(name: &str) -> Result<Option<PathBuf>, String> {
    if !valid_name(name) {
        return Err(format!("artifact name must be a filename: {name:?}"));
    }
    let root = match std::env::var_os("SNAIL_ARTIFACT_ROOT") {
        Some(path) => PathBuf::from(path),
        None => {
            #[cfg(all(feature = "native-runtime", not(target_arch = "wasm32"), not(test)))]
            {
                let executable = std::env::current_exe().map_err(|error| error.to_string())?;
                executable
                    .parent()
                    .ok_or("native executable has no directory")?
                    .join("artifacts")
            }
            #[cfg(any(not(feature = "native-runtime"), target_arch = "wasm32", test))]
            return Ok(None);
        }
    };
    find_in(root, name)
}

#[unsafe(export_name = "snail:find-artifact")]
pub extern "C" fn find_artifact(raw: u32) -> u32 {
    let args = arguments(raw, "find-artifact", 1, 1);
    finish((|| {
        let name = string_text(&args.get(0)?)?;
        match find(&name)? {
            Some(path) => Ok(Root::string(
                path.to_str().ok_or("artifact path is not UTF-8")?,
            )),
            None => Ok(Root::boolean(false)),
        }
    })())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_are_single_components() {
        for name in ["", ".", "..", "../runtime", "a/b", "a\\b", "a\0b"] {
            assert!(!valid_name(name), "{name:?}");
        }
        assert!(valid_name("runtime 'λ.wat"));
    }

    #[test]
    fn lookup_distinguishes_missing_files_and_directories() {
        let root =
            std::env::temp_dir().join(format!("snail-artifact-lookup-{}", std::process::id()));
        std::fs::create_dir(&root).unwrap();
        std::fs::write(root.join("runtime 'λ.wat"), b"(module)").unwrap();
        std::fs::create_dir(root.join("directory")).unwrap();
        assert_eq!(
            find_in(root.clone(), "runtime 'λ.wat").unwrap(),
            Some(root.join("runtime 'λ.wat"))
        );
        assert_eq!(find_in(root.clone(), "missing").unwrap(), None);
        assert!(find_in(root.clone(), "directory").is_err());
        assert!(find_in(root.clone(), "../escape").is_err());
        std::fs::remove_dir_all(root).unwrap();
    }
}
