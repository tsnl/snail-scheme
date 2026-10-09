//! Cargo owns the executable and target runtime libraries. LLVM only assembles
//! the generated Scheme program into one target object for Cargo to link.

use std::{
    env,
    path::{Path, PathBuf},
    process::Command,
};

fn main() {
    println!("cargo:rerun-if-env-changed=SNAIL_LLVM_IR");
    println!("cargo:rerun-if-env-changed=LLVM_LLC");
    let input = input_path();
    let object = PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("scheme.o");
    println!("cargo:rerun-if-changed={}", input.display());
    assemble(&input, &object);
    println!("cargo:rustc-link-arg={}", object.display());
}

fn input_path() -> PathBuf {
    let manifest = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let input = env::var_os("SNAIL_LLVM_IR")
        .map(PathBuf::from)
        .expect("set SNAIL_LLVM_IR to the Scheme compiler's generated .ll file");
    manifest
        .parent()
        .unwrap()
        .join(input)
        .canonicalize()
        .expect("cannot read SNAIL_LLVM_IR input file")
}

fn llvm_target(target: &str) -> &str {
    match target {
        "wasm32-wasip1" => "wasm32-unknown-wasip1",
        other => other,
    }
}

fn assembler(target: &str) -> Command {
    let llc = env::var_os("LLVM_LLC").unwrap_or_else(|| "llc".into());
    let mut command = Command::new(llc);
    command.args(["-filetype=obj", "-mtriple", llvm_target(target)]);
    if !target.starts_with("wasm") {
        command.arg("-relocation-model=pic");
    }
    command
}

fn assemble(input: &Path, object: &Path) {
    let target = env::var("TARGET").unwrap();
    let status = assembler(&target)
        .arg(input)
        .arg("-o")
        .arg(object)
        .status()
        .expect("cannot execute llc; set LLVM_LLC to its path");
    assert!(status.success(), "llc failed compiling {}", input.display());
}
