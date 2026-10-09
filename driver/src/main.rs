//! Local compiler command: Scheme emits LLVM; Cargo builds or runs the program.
//! Each invocation owns a Cargo project, so concurrent builds cannot replace
//! one another's executable. Subprocess arguments never pass through a shell.

use std::{
    env,
    ffi::OsString,
    fs,
    io::{self, Write},
    path::{Path, PathBuf},
    process::{Command, ExitStatus},
    time::{Instant, SystemTime, UNIX_EPOCH},
};

type Result<T> = std::result::Result<T, String>;

const HELP: &str = "Usage: snail-scheme INPUT.scm [OPTIONS] [-- ARG ...]

Run a Scheme program, or build an executable with -o.
  -o, --output, --out PATH  Build and copy the executable without running it
  --emit-llvm              Emit LLVM text instead (stdout, or -o PATH)
  --target TARGET          native (default) or wasm32-wasip1
  --release                Optimize the runtime when running (builds use release)
  --dump-vm PATH           Also write the readable stack-VM program
  --timing                 Report compiler stages and Cargo time on stderr
  --runtime-stats          Report execution and GC statistics on stderr
  --keep-build             Keep this invocation's generated Cargo project
  -h, --help               Show this help

Program arguments after -- are passed literally and require run mode.
CHIBI, NODE, LLVM_LLC and LLVM_OPT select tool executables.";

// ---- Arguments and execution modes ---------------------------------------

#[derive(Default, Debug)]
struct Options {
    input: PathBuf,
    output: Option<PathBuf>,
    dump: Option<PathBuf>,
    wasm: bool,
    emit: bool,
    release: bool,
    timing: bool,
    statistics: bool,
    keep: bool,
    help: bool,
    arguments: Vec<OsString>,
}

enum Action {
    Run,
    Build(PathBuf),
    Emit(Option<PathBuf>),
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

fn parse_argument(
    argument: OsString,
    rest: &mut impl Iterator<Item = OsString>,
    options: &mut Options,
) -> Result<()> {
    match argument.to_str() {
        Some("-o" | "--output" | "--out") => {
            options.output = Some(option_value(rest, "-o")?.into())
        }
        Some("--dump-vm") => options.dump = Some(option_value(rest, "--dump-vm")?.into()),
        Some("--target") => options.wasm = target(&option_value(rest, "--target")?)?,
        Some("--emit-llvm") => options.emit = true,
        Some("--release") => options.release = true,
        Some("--timing") => options.timing = true,
        Some("--runtime-stats") => options.statistics = true,
        Some("--keep-build") => options.keep = true,
        Some("-h" | "--help") => options.help = true,
        Some(flag) if flag.starts_with('-') => return Err(format!("unknown option: {flag}")),
        _ if options.input.as_os_str().is_empty() => options.input = argument.into(),
        _ => return Err("expected one input file; program arguments must follow --".into()),
    }
    Ok(())
}

fn target(value: &OsString) -> Result<bool> {
    match value.to_str() {
        Some("native") => Ok(false),
        Some("wasm32-wasip1") => Ok(true),
        _ => Err("--target must be native or wasm32-wasip1".into()),
    }
}

fn validate_options(options: &Options) -> Result<()> {
    if options.help {
        return Ok(());
    }
    if options.input.as_os_str().is_empty() {
        return Err("expected an input file".into());
    }
    if !options.arguments.is_empty() && (options.output.is_some() || options.emit) {
        return Err("program arguments require run mode (no -o or --emit-llvm)".into());
    }
    if options.statistics && (options.output.is_some() || options.emit) {
        return Err("--runtime-stats requires run mode".into());
    }
    Ok(())
}

// ---- Invocation-owned files ---------------------------------------------

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
            name.set_extension("ll");
        } else if options.wasm {
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
    if destination_identity(&resolved) == input {
        return Err("output must not replace the source file".into());
    }
    Ok(resolved)
}

fn destination_identity(path: &Path) -> PathBuf {
    path.canonicalize().unwrap_or_else(|_| path.to_owned())
}

fn prepare_outputs(options: &Options, input: &Path) -> Result<(Option<PathBuf>, Option<PathBuf>)> {
    let output = output_path(options)
        .map(|path| prepare_output(&path, input))
        .transpose()?;
    let dump = options
        .dump
        .as_ref()
        .map(|path| prepare_output(path, input))
        .transpose()?;
    if let (Some(output), Some(dump)) = (&output, &dump)
        && destination_identity(output) == destination_identity(dump)
    {
        return Err("executable/LLVM output and VM dump must differ".into());
    }
    Ok((output, dump))
}

// ---- Scheme emission and Cargo project ----------------------------------

fn compile(
    root: &Path,
    project: &Project,
    input: &Path,
    dump: bool,
    options: &Options,
) -> Result<()> {
    let mut command = Command::new(root.join("snail-compile"));
    command.arg(input).arg(project.path("program.ll"));
    if dump {
        command.arg(project.path("program.vm"));
    }
    if options.timing {
        command.arg("--timing");
    }
    require_success(&mut command, "Scheme compilation")
}

fn toml_string(value: &str) -> String {
    let mut result = String::from("\"");
    for character in value.chars() {
        match character {
            '"' => result.push_str("\\\""),
            '\\' => result.push_str("\\\\"),
            c if c.is_control() => result.push_str(&format!("\\u{:04X}", c as u32)),
            c => result.push(c),
        }
    }
    result.push('"');
    result
}

fn quoted_path(path: &Path) -> Result<String> {
    path.to_str()
        .map(toml_string)
        .ok_or_else(|| "Cargo project paths must be UTF-8".into())
}

fn write_manifest(root: &Path, project: &Project) -> Result<()> {
    let manifest = format!(
        "[package]\nname = \"snail-program\"\nversion = \"0.0.0\"\nedition = \"2024\"\nbuild = {}\n\n[[bin]]\nname = \"snail-program\"\npath = {}\n\n[dependencies]\nsnail-runtime = {{ path = {} }}\n\n[profile.release]\npanic = \"abort\"\n\n[workspace]\n",
        quoted_path(&root.join("runner/build.rs"))?,
        quoted_path(&root.join("runner/src/main.rs"))?,
        quoted_path(&root.join("runtime"))?
    );
    fs::write(project.path("Cargo.toml"), manifest).map_err(message)
}

fn wasm_runner(root: &Path) -> Result<String> {
    let node = env::var("NODE").unwrap_or_else(|_| "node".into());
    Ok(format!(
        "target.wasm32-wasip1.runner=[{},\"--no-warnings\",{}]",
        toml_string(&node),
        quoted_path(&root.join("scripts/run-wasi.mjs"))?
    ))
}

fn cargo_command(
    root: &Path,
    project: &Project,
    options: &Options,
    action: &Action,
) -> Result<Command> {
    let mut command = Command::new(env::var_os("CARGO").unwrap_or_else(|| "cargo".into()));
    command.arg(if matches!(action, Action::Run) {
        "run"
    } else {
        "build"
    });
    command
        .args(["--quiet", "--offline", "--manifest-path"])
        .arg(project.path("Cargo.toml"));
    command.arg("--target-dir").arg(project.path("target"));
    configure_target(&mut command, root, options, action)?;
    command.env("SNAIL_LLVM_IR", project.path("program.ll"));
    if options.statistics {
        command.env("SNAIL_RUNTIME_STATS", "1");
    }
    Ok(command)
}

fn configure_target(
    command: &mut Command,
    root: &Path,
    options: &Options,
    action: &Action,
) -> Result<()> {
    if options.release || matches!(action, Action::Build(_)) {
        command.arg("--release");
    }
    if options.wasm {
        command
            .args(["--target", "wasm32-wasip1", "--config"])
            .arg(wasm_runner(root)?);
    }
    if matches!(action, Action::Run) {
        command.arg("--").args(&options.arguments);
    }
    Ok(())
}

fn require_success(command: &mut Command, stage: &str) -> Result<()> {
    let status = command
        .status()
        .map_err(|error| format!("{stage}: {error}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("{stage} failed: {status}"))
    }
}

fn artifact(project: &Project, wasm: bool) -> PathBuf {
    if wasm {
        project.path("target/wasm32-wasip1/release/snail-program.wasm")
    } else {
        project.path(&format!(
            "target/release/snail-program{}",
            env::consts::EXE_SUFFIX
        ))
    }
}

// Publish only a completed artifact. Failed compilation leaves an existing
// destination untouched; rename also permits replacing an executing Unix file.
fn publish(source: &Path, destination: &Path) -> Result<()> {
    let staging = destination.with_extension(format!("snail-{}-tmp", std::process::id()));
    // Reserve our staging name before writing; never truncate someone else's file.
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

fn emit(project: &Project, output: Option<&Path>) -> Result<i32> {
    match output {
        Some(path) => publish(&project.path("program.ll"), path)?,
        None => io::stdout()
            .write_all(&fs::read(project.path("program.ll")).map_err(message)?)
            .map_err(message)?,
    }
    Ok(0)
}

// ---- Entry point ---------------------------------------------------------

fn execute(options: Options) -> Result<i32> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
    let input = options.input.canonicalize().map_err(message)?;
    let (output, dump) = prepare_outputs(&options, &input)?;
    let project = Project::create(root, options.keep)?;
    compile(root, &project, &input, dump.is_some(), &options)?;
    if let Some(dump) = dump {
        publish(&project.path("program.vm"), &dump)?;
    }
    let action = match (options.emit, output) {
        (true, output) => Action::Emit(output),
        (false, Some(output)) => Action::Build(output),
        (false, None) => Action::Run,
    };
    if let Action::Emit(output) = action {
        return emit(&project, output.as_deref());
    }
    write_manifest(root, &project)?;
    build_or_run(root, &project, &action, &options)
}

fn build_or_run(root: &Path, project: &Project, action: &Action, options: &Options) -> Result<i32> {
    let start = Instant::now();
    let status = cargo_command(root, project, options, action)?
        .status()
        .map_err(message)?;
    if options.timing {
        let phase = if matches!(action, Action::Run) {
            "cargo-build-and-run"
        } else {
            "cargo-build"
        };
        eprintln!("compiler: {phase} {} us", start.elapsed().as_micros());
    }
    if status.success()
        && let Action::Build(output) = action
    {
        publish(&artifact(project, options.wasm), output)?;
    }
    Ok(exit_code(status))
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
