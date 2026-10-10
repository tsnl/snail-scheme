//! Scheme and Rust meet as WebAssembly modules. Native code is an optional
//! postprocessing step; the compiler's output is always WebAssembly.

use std::{
    env,
    ffi::OsString,
    fs,
    io::{self, Write},
    path::{Path, PathBuf},
    process::{Command, ExitStatus},
    time::{SystemTime, UNIX_EPOCH},
};

type Result<T> = std::result::Result<T, String>;

const HELP: &str = "Usage: snail-scheme INPUT.scm [OPTIONS] [-- ARG ...]

Run a Scheme program in WebAssembly, or build a module with -o.
  -o, --output PATH        Build without running (a directory is also accepted)
  --emit-wat              Emit Scheme WAT before linking (stdout, or -o PATH)
  --native                Compile Wasm using SNAIL_WASM_NATIVE (INPUT -o OUTPUT)
  --extension PATH        Link a Rust crate with [package.metadata.snail] exports
  --release               Accepted for compatibility; builds are always optimized
  --keep-build            Keep this invocation's intermediate files
  -h, --help               Show this help

Program arguments after -- are passed literally and require run mode.
Traces are always saved under build/traces/ (override with SNAIL_TRACE_DIR).
CHIBI, CARGO, NODE, WASM_AS, WASM_MERGE, WASM_OPT select tools.";

const FEATURES: &[&str] = &[
    "--mvp-features",
    "--enable-gc",
    "--enable-reference-types",
    "--enable-tail-call",
    "--enable-mutable-globals",
    "--enable-sign-ext",
    "--enable-bulk-memory",
];

// An explicit reactor initializer prevents wasm-ld from wrapping each export in
// constructor/destructor calls. The Wasm entry module invokes it exactly once.
const RUST_START: &str = r#"pub use runtime::*;
unsafe extern "C" { fn __wasm_call_ctors(); }
#[unsafe(no_mangle)]
pub unsafe extern "C" fn _initialize() { unsafe { __wasm_call_ctors(); } }
"#;

const START: &str = r#"(module
  (import "snail.awi" "snail_main" (func $main (result eqref)))
  (import "snail.rust" "_initialize" (func $initialize))
  (func (export "_start") (call $initialize) (drop (call $main))))
"#;

// ---- Arguments and execution modes ----

#[derive(Default, Debug)]
struct Options {
    input: PathBuf,
    output: Option<PathBuf>,
    extensions: Vec<PathBuf>,
    emit: bool,
    native: bool,
    keep: bool,
    help: bool,
    arguments: Vec<OsString>,
}

fn option_value(arguments: &mut impl Iterator<Item = OsString>, flag: &str) -> Result<OsString> {
    arguments
        .next()
        .ok_or_else(|| format!("{flag} requires a value"))
}

fn parse(arguments: impl IntoIterator<Item = OsString>) -> Result<Options> {
    let mut options = Options::default();
    let mut arguments = arguments.into_iter();
    while let Some(argument) = arguments.next() {
        if argument == "--" {
            options.arguments.extend(arguments);
            break;
        }
        parse_argument(argument, &mut arguments, &mut options)?;
    }
    validate_options(&options)?;
    Ok(options)
}

// Keep the complete command-line vocabulary together.
fn parse_argument(
    argument: OsString,
    rest: &mut impl Iterator<Item = OsString>,
    options: &mut Options,
) -> Result<()> {
    match argument.to_str() {
        Some("-o" | "--output" | "--out") => {
            options.output = Some(option_value(rest, "-o")?.into())
        }
        Some("--emit-wat") => options.emit = true,
        Some("--native") => options.native = true,
        Some("--extension") => options
            .extensions
            .push(option_value(rest, "--extension")?.into()),
        Some("--target") => options.native = native_target(&option_value(rest, "--target")?)?,
        Some("--release") => (),
        Some("--keep-build") => options.keep = true,
        Some("-h" | "--help") => options.help = true,
        Some("--emit-llvm" | "--dump-mir" | "--dump-vm") => {
            return Err("LLVM and MIR output were retired; use --emit-wat".into());
        }
        Some(flag) if flag.starts_with('-') => return Err(format!("unknown option: {flag}")),
        _ if options.input.as_os_str().is_empty() => options.input = argument.into(),
        _ => return Err("expected one input file; program arguments must follow --".into()),
    }
    Ok(())
}

fn native_target(value: &OsString) -> Result<bool> {
    match value.to_str() {
        Some("wasm" | "wasm32-wasip1") => Ok(false),
        Some("native") => Ok(true),
        _ => Err("--target must be wasm32-wasip1 or native".into()),
    }
}

fn validate_options(options: &Options) -> Result<()> {
    if options.help {
        return Ok(());
    }
    if options.input.as_os_str().is_empty() {
        return Err("expected an input file".into());
    }
    if options.emit && options.native {
        return Err("--emit-wat and --native select different outputs".into());
    }
    if !options.arguments.is_empty() && (options.output.is_some() || options.emit) {
        return Err("program arguments require run mode (no -o or --emit-wat)".into());
    }
    Ok(())
}

// ---- Invocation-owned files ----

struct Project {
    directory: PathBuf,
    keep: bool,
}

impl Project {
    fn create(root: &Path, keep: bool) -> Result<Self> {
        let time = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(message)?
            .as_nanos();
        let directory = root
            .join("build/cli")
            .join(format!("{}-{time}", std::process::id()));
        fs::create_dir_all(directory.parent().unwrap()).map_err(message)?;
        fs::create_dir(&directory).map_err(message)?;
        Ok(Self { directory, keep })
    }

    fn path(&self, name: &str) -> PathBuf {
        self.directory.join(name)
    }
}

impl Drop for Project {
    fn drop(&mut self) {
        if self.keep {
            eprintln!("build project: {}", self.directory.display());
        } else {
            let _ = fs::remove_dir_all(&self.directory);
        }
    }
}

fn message(error: impl std::fmt::Display) -> String {
    error.to_string()
}

fn output_path(options: &Options) -> Option<PathBuf> {
    options.output.as_ref().map(|path| {
        if !path.is_dir() {
            return path.clone();
        }
        let mut name = PathBuf::from(options.input.file_stem().unwrap_or_default());
        if options.emit {
            name.set_extension("wat");
        } else if !options.native {
            name.set_extension("wasm");
        } else if cfg!(windows) {
            name.set_extension("exe");
        }
        path.join(name)
    })
}

fn prepare_output(path: &Path, input: &Path) -> Result<PathBuf> {
    let absolute = env::current_dir().map_err(message)?.join(path);
    let parent = absolute.parent().ok_or("output has no parent directory")?;
    fs::create_dir_all(parent).map_err(message)?;
    let resolved = parent
        .canonicalize()
        .map_err(message)?
        .join(absolute.file_name().ok_or("output needs a filename")?);
    if resolved.canonicalize().unwrap_or_else(|_| resolved.clone()) == input {
        return Err("output must not replace the source file".into());
    }
    Ok(resolved)
}

// Reserve a separate file, then atomically publish only a completed artifact.
// A failed compiler or linker never truncates a previously successful output.
fn publish(source: &Path, destination: &Path) -> Result<()> {
    let staging = destination.with_extension(format!("snail-{}-tmp", std::process::id()));
    fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&staging)
        .map_err(message)?;
    let result = fs::copy(source, &staging).and_then(|_| fs::rename(&staging, destination));
    if result.is_err() {
        let _ = fs::remove_file(&staging);
    }
    result.map_err(message)
}

fn publish_wat(project: &Project, output: Option<&Path>) -> Result<i32> {
    match output {
        Some(path) => publish(&project.path("program.wat"), path)?,
        None => io::stdout()
            .write_all(&fs::read(project.path("program.wat")).map_err(message)?)
            .map_err(message)?,
    }
    Ok(0)
}

// ---- Scheme and Rust WebAssembly modules ----

fn tool(variable: &str, default: &str) -> Command {
    Command::new(env::var_os(variable).unwrap_or_else(|| default.into()))
}

fn require_success(command: &mut Command, stage: &str) -> Result<()> {
    let _trace = snail_trace::span(stage);
    let status = command
        .status()
        .map_err(|error| format!("{stage}: {error}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("{stage} failed: {status}"))
    }
}

fn source_file_to_wasm(
    root: &Path,
    project: &Project,
    input: &Path,
    extensions: &[Extension],
) -> Result<()> {
    let mut command = Command::new(root.join("snail-compile"));
    command.env(
        "SNAIL_TRACE_DIR",
        snail_trace::directory().map_err(message)?,
    );
    command.arg(input).arg(project.path("program.wat"));
    for extension in extensions {
        for name in &extension.exports {
            command.arg("snail.rust").arg(name);
        }
    }
    require_success(&mut command, "driver.source-file-to-wasm")
}

fn assemble(input: &Path, output: &Path) -> Result<()> {
    let mut command = tool("WASM_AS", "wasm-as");
    command.args(FEATURES).arg(input).arg("-o").arg(output);
    require_success(&mut command, "driver.assemble-wasm")
}

// Each extension is a Rust library. One generated cdylib combines them with the
// runtime before Wasm linking: all Rust pointers then refer to the same memory.
struct Extension {
    name: String,
    directory: PathBuf,
    exports: Vec<String>,
}

fn extension_metadata(path: &Path) -> Result<Extension> {
    let manifest = if path.is_dir() {
        path.join("Cargo.toml")
    } else {
        path.to_owned()
    }
    .canonicalize()
    .map_err(message)?;
    let metadata = read_cargo_metadata(&manifest)?;
    let packages = metadata["packages"]
        .as_array()
        .ok_or("Cargo metadata has no packages")?;
    let package = packages
        .iter()
        .find(|p| p["manifest_path"].as_str().map(Path::new) == Some(manifest.as_path()))
        .ok_or("extension manifest must name a package")?;
    let exports = extension_exports(package)?;
    let name = package["name"]
        .as_str()
        .ok_or("extension package has no name")?
        .into();
    Ok(Extension {
        name,
        directory: manifest.parent().unwrap().to_owned(),
        exports,
    })
}

fn read_cargo_metadata(manifest: &Path) -> Result<serde_json::Value> {
    let output = tool("CARGO", "cargo")
        .args([
            "metadata",
            "--offline",
            "--no-deps",
            "--format-version",
            "1",
            "--manifest-path",
        ])
        .arg(manifest)
        .output()
        .map_err(message)?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).into_owned());
    }
    serde_json::from_slice(&output.stdout).map_err(message)
}

fn extension_exports(package: &serde_json::Value) -> Result<Vec<String>> {
    package["metadata"]["snail"]["exports"]
        .as_array()
        .ok_or("extension needs [package.metadata.snail] exports = [\"scheme-name\"]")?
        .iter()
        .map(|value| {
            value
                .as_str()
                .filter(|name| !name.is_empty())
                .map(str::to_owned)
                .ok_or_else(|| "extension exports must be nonempty strings".into())
        })
        .collect()
}

fn toml_string(value: &str) -> String {
    // JSON string escapes are also valid TOML basic-string escapes for paths and names.
    serde_json::to_string(value).unwrap()
}

fn quoted_path(path: &Path) -> Result<String> {
    path.to_str()
        .map(toml_string)
        .ok_or_else(|| "Cargo project paths must be UTF-8".into())
}

fn write_manifest(root: &Path, project: &Project, extensions: &[Extension]) -> Result<String> {
    let name = format!(
        "snail-program-{}",
        project.directory.file_name().unwrap().to_string_lossy()
    );
    let mut manifest = format!(
        "[package]\nname = {}\nversion = \"0.0.0\"\nedition = \"2024\"\n[lib]\npath = \"lib.rs\"\ncrate-type = [\"cdylib\"]\n[workspace]\n[profile.release]\npanic = \"abort\"\nlto = true\ncodegen-units = 1\n[dependencies]\nruntime = {{ package = \"snail-runtime\", path = {} }}\n",
        toml_string(&name),
        quoted_path(&root.join("runtime"))?
    );
    let mut source = String::from(RUST_START);
    for (index, extension) in extensions.iter().enumerate() {
        manifest.push_str(&format!(
            "extension_{index} = {{ package = {}, path = {} }}\n",
            toml_string(&extension.name),
            quoted_path(&extension.directory)?
        ));
        source.push_str(&format!("pub use extension_{index}::*;\n"));
    }
    fs::write(project.path("Cargo.toml"), manifest).map_err(message)?;
    fs::write(project.path("lib.rs"), source).map_err(message)?;
    Ok(name.replace('-', "_"))
}

fn build_runtime(root: &Path, project: &Project, extensions: &[Extension]) -> Result<PathBuf> {
    let name = write_manifest(root, project, extensions)?;
    let target = root.join("build/wasm-runtime");
    let mut command = tool("CARGO", "cargo");
    command.current_dir(root).args([
        "build",
        "--quiet",
        "--offline",
        "--release",
        "--target",
        "wasm32-wasip1",
    ]);
    command
        .arg("--manifest-path")
        .arg(project.path("Cargo.toml"))
        .arg("--target-dir")
        .arg(&target);
    require_success(&mut command, "driver.cargo-build")?;
    let output = project.path("rust.wasm");
    fs::copy(
        target.join(format!("wasm32-wasip1/release/{name}.wasm")),
        &output,
    )
    .map_err(message)?;
    Ok(output)
}

fn merge_modules(project: &Project, runtime: &Path) -> Result<()> {
    fs::write(project.path("start.wat"), START).map_err(message)?;
    assemble(&project.path("start.wat"), &project.path("start.wasm"))?;
    let mut command = tool("WASM_MERGE", "wasm-merge");
    command
        .args(FEATURES)
        .arg(project.path("scheme.wasm"))
        .arg("snail.awi");
    command
        .arg(runtime)
        .arg("snail.rust")
        .arg(project.path("start.wasm"))
        .arg("snail.entry");
    command.arg("-o").arg(project.path("linked.wasm"));
    require_success(&mut command, "driver.link-wasm")
}

fn optimize_module(project: &Project) -> Result<PathBuf> {
    let mut command = tool("WASM_OPT", "wasm-opt");
    let output = project.path("program.wasm");
    command
        .args(FEATURES)
        .args([
            "--remove-exports",
            "--pass-arg=remove-exports@_initialize",
            "-O3",
            "--closed-world",
            // Revisit tiny helpers exposed by earlier passes, keeping checks.
            "--always-inline-max-function-size=40",
            "--converge",
        ])
        .arg(project.path("linked.wasm"))
        .arg("-o")
        .arg(&output);
    require_success(&mut command, "driver.optimize-wasm")?;
    Ok(output)
}

fn build_wasm(root: &Path, project: &Project, extensions: &[Extension]) -> Result<PathBuf> {
    assemble(&project.path("program.wat"), &project.path("scheme.wasm"))?;
    let runtime = build_runtime(root, project, extensions)?;
    merge_modules(project, &runtime)?;
    optimize_module(project)
}

fn compile_native(project: &Project, wasm: &Path) -> Result<PathBuf> {
    let output = project.path("program");
    let compiler = env::var_os("SNAIL_WASM_NATIVE")
        .ok_or("--native needs SNAIL_WASM_NATIVE, a compiler accepting INPUT.wasm -o OUTPUT")?;
    let mut command = Command::new(compiler);
    command.arg(wasm).arg("-o").arg(&output);
    require_success(&mut command, "driver.native-compile")?;
    Ok(output)
}

fn run_program(root: &Path, artifact: &Path, options: &Options) -> Result<i32> {
    let _trace = snail_trace::span("driver.run");
    let mut command = if options.native {
        Command::new(artifact)
    } else {
        tool("NODE", "node")
    };
    if !options.native {
        command
            .arg("--no-warnings")
            .arg(root.join("scripts/run-wasi.mjs"))
            .arg(artifact);
    }
    command.args(&options.arguments).env(
        "SNAIL_TRACE_DIR",
        snail_trace::directory().map_err(message)?,
    );
    command.status().map(exit_code).map_err(message)
}

// ---- Entry point ----

fn execute(options: Options) -> Result<i32> {
    let _trace = snail_trace::span("driver.execute");
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
    let input = options.input.canonicalize().map_err(message)?;
    let output = output_path(&options)
        .map(|path| prepare_output(&path, &input))
        .transpose()?;
    let project = Project::create(root, options.keep)?;
    let extensions = options
        .extensions
        .iter()
        .map(|path| extension_metadata(path))
        .collect::<Result<Vec<_>>>()?;
    source_file_to_wasm(root, &project, &input, &extensions)?;
    if options.emit {
        return publish_wat(&project, output.as_deref());
    }
    let wasm = build_wasm(root, &project, &extensions)?;
    let artifact = if options.native {
        compile_native(&project, &wasm)?
    } else {
        wasm
    };
    if let Some(output) = output {
        publish(&artifact, &output)?;
        Ok(0)
    } else {
        run_program(root, &artifact, &options)
    }
}

fn exit_code(status: ExitStatus) -> i32 {
    status.code().unwrap_or(1)
}

fn main() {
    let outcome = parse(env::args_os().skip(1)).and_then(|options| {
        if options.help {
            println!("{HELP}");
            Ok(0)
        } else {
            execute(options)
        }
    });
    match outcome {
        Ok(code) => std::process::exit(code),
        Err(error) => {
            eprintln!("snail-scheme: {error}\nUse --help for invocation details.");
            std::process::exit(1);
        }
    }
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    fn arguments(values: &[&str]) -> Result<Options> {
        parse(values.iter().map(OsString::from))
    }

    #[test]
    fn modes_and_literal_arguments() {
        let options = arguments(&["source.scm", "--", "", "--help", "space here"]).unwrap();
        assert_eq!(options.arguments, ["", "--help", "space here"]);
        assert!(!options.help);
        assert!(arguments(&["source.scm", "--native", "--emit-wat"]).is_err());
        assert!(arguments(&["source.scm", "-o", "out", "--", "arg"]).is_err());
        assert_eq!(
            arguments(&["source.scm", "-o", "--help"]).unwrap().output,
            Some(PathBuf::from("--help"))
        );
    }

    #[test]
    fn temporary_project_is_cleaned_on_drop() {
        let root = env::temp_dir().join(format!("snail-driver-test-{}", std::process::id()));
        let project = Project::create(&root, false).unwrap();
        let directory = project.directory.clone();
        assert!(directory.is_dir());
        drop(project);
        assert!(!directory.exists());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn obsolete_modes_fail_clearly() {
        assert!(
            arguments(&["source.scm", "--emit-llvm"])
                .unwrap_err()
                .contains("retired")
        );
        assert!(arguments(&["source.scm", "--target", "unknown"]).is_err());
        assert!(arguments(&["--help"]).unwrap().help);
        assert!(arguments(&[]).is_err());
    }
}
