//! Specialize the Scheme-written instruction functions, then let Cargo link the
//! resulting object with Rust. No Rust bitcode or handwritten LLVM is required.

use std::{
    env, fs,
    path::{Path, PathBuf},
    process::Command,
};

fn main() {
    watch_environment();
    let input = input_path();
    let output = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    let target = env::var("TARGET").unwrap();
    println!("cargo:rerun-if-changed={}", input.display());
    let module = prepare_module(&input, &output, &target);
    let optimized = optimize(&module, &output);
    let object = assemble(&optimized, &output, &target);
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

fn prepare_module(input: &Path, output: &Path, target: &str) -> PathBuf {
    assert!(matches!(
        env::var("CARGO_CFG_TARGET_POINTER_WIDTH").unwrap().as_str(),
        "32" | "64"
    ));
    let metadata = target_metadata(output, target);
    assert!(metadata.contains("target datalayout =") && metadata.contains("target triple ="));
    let module = output.join("scheme.target.ll");
    fs::write(&module, metadata + &fs::read_to_string(input).unwrap()).unwrap();
    module
}

fn optimize(input: &Path, output: &Path) -> PathBuf {
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

fn assemble(input: &Path, output: &Path, target: &str) -> PathBuf {
    let object = output.join("scheme.o");
    let mut command = Command::new(env::var_os("LLVM_LLC").unwrap_or_else(|| "llc".into()));
    command.arg("-filetype=obj");
    if !target.starts_with("wasm") {
        command.arg("-relocation-model=pic");
    }
    run(command.arg(input).arg("-o").arg(&object));
    object
}
