//! Specialize the Scheme-written instruction functions, then let Cargo link the
//! resulting object with Rust. No Rust bitcode or handwritten LLVM is required.

use std::{
    env, fs,
    path::{Path, PathBuf},
    process::Command,
};

fn main() {
    let _trace = snail_trace::span("build.llvm-to-object");
    watch_environment();
    let input = input_path();
    let output = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    let target = env::var("TARGET").unwrap();
    println!("cargo:rerun-if-changed={}", input.display());
    let module = llvm_ir_with_target_layout(&input, &output, &target);
    let optimized = optimize_llvm_ir(&module, &output);
    let object = llvm_ir_to_object(&optimized, &output, &target);
    println!("cargo:rustc-link-arg={}", object.display());
}

fn watch_environment() {
    for name in ["SNAIL_LLVM_IR", "LLVM_LLC", "LLVM_OPT"] {
        println!("cargo:rerun-if-env-changed={name}");
    }
}

fn input_path() -> PathBuf {
    let manifest = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let input = env::var_os("SNAIL_LLVM_IR")
        .expect("set SNAIL_LLVM_IR to the Scheme compiler's generated .ll file");
    manifest
        .parent()
        .unwrap()
        .join(input)
        .canonicalize()
        .expect("cannot read SNAIL_LLVM_IR input file")
}

fn run(command: &mut Command) {
    let status = command
        .status()
        .unwrap_or_else(|error| panic!("{command:?}: {error}"));
    assert!(status.success(), "command failed: {command:?}");
}

// Ask the same rustc that Cargo uses for the target's actual LLVM layout. The
// tiny no_std probe needs only core, already required by the target runtime.
fn target_metadata(output: &Path, target: &str) -> String {
    let _trace = snail_trace::span("build.target-layout");
    let source = output.join("target_layout.rs");
    let ir = output.join("target_layout.ll");
    fs::write(&source, "#![no_std]\n").unwrap();
    run(Command::new(env::var_os("RUSTC").unwrap())
        .args(["--crate-type=lib", "--emit=llvm-ir", "--target", target])
        .arg(source)
        .arg("-o")
        .arg(&ir));
    fs::read_to_string(ir)
        .unwrap()
        .lines()
        .filter(|line| line.starts_with("target "))
        .map(|line| format!("{line}\n"))
        .collect()
}

fn llvm_ir_with_target_layout(input: &Path, output: &Path, target: &str) -> PathBuf {
    assert_eq!(
        env::var("CARGO_CFG_TARGET_POINTER_WIDTH").unwrap(),
        "32",
        "the runtime requires 32-bit pointers; use --target i686-unknown-linux-musl or wasm32-wasip1"
    );
    let metadata = target_metadata(output, target);
    assert!(metadata.contains("target datalayout =") && metadata.contains("target triple ="));
    let module = output.join("scheme.target.ll");
    fs::write(&module, metadata + &fs::read_to_string(input).unwrap()).unwrap();
    module
}

fn optimize_llvm_ir(input: &Path, output: &Path) -> PathBuf {
    let _trace = snail_trace::span("build.optimize-llvm");
    let optimized = output.join("scheme.optimized.ll");
    run(
        Command::new(env::var_os("LLVM_OPT").unwrap_or_else(|| "opt".into()))
            .args(["-S", "-passes=always-inline,default<O2>,verify"])
            .arg(input)
            .arg("-o")
            .arg(&optimized),
    );
    let text = fs::read_to_string(&optimized).unwrap();
    // A compiled compiler contains handler names in its string constants.
    // Only remaining function definitions indicate failed specialization.
    assert!(
        !text
            .lines()
            .any(|line| line.starts_with("define ") && line.contains("@snail_vm_")),
        "VM instruction functions were not fully inlined"
    );
    optimized
}

fn llvm_ir_to_object(input: &Path, output: &Path, target: &str) -> PathBuf {
    let _trace = snail_trace::span("build.llvm-to-object-code");
    let object = output.join("scheme.o");
    let mut command = Command::new(env::var_os("LLVM_LLC").unwrap_or_else(|| "llc".into()));
    command.arg("-filetype=obj");
    if target.starts_with("wasm") {
        verify_reducible(input);
        // All VM cycles use the dispatcher. LLVM 22's redundant repair pass
        // computes quadratic reachability sets for the compiler-sized loop.
        command.arg("--wasm-disable-fix-irreducible-control-flow-pass");
    } else {
        command.arg("-relocation-model=pic");
    }
    run(command.arg(input).arg("-o").arg(&object));
    object
}

fn verify_reducible(input: &Path) {
    let _trace = snail_trace::span("build.verify-reducible");
    let report = Command::new(env::var_os("LLVM_OPT").unwrap_or_else(|| "opt".into()))
        .args(["-passes=print<cycles>", "-disable-output"])
        .arg(input)
        .output()
        .expect("cannot check optimized LLVM cycles");
    let text = String::from_utf8_lossy(&report.stderr);
    assert!(
        report.status.success(),
        "LLVM cycle analysis failed: {text}"
    );
    assert!(
        text.lines()
            .any(|line| line == "CycleInfo for function: snail_program"),
        "unrecognized LLVM cycle report"
    );
    assert!(
        text.lines()
            .filter(|line| line.trim_start().starts_with("depth="))
            .all(single_cycle_entry),
        "WASM requires reducible optimized control flow"
    );
}

fn single_cycle_entry(line: &str) -> bool {
    line.split_once("entries(")
        .and_then(|(_, tail)| tail.split_once(')'))
        .is_some_and(|(entries, _)| entries.split_whitespace().count() == 1)
}
