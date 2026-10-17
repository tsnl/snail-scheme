//! Runtime linked with this package's mechanically lowered WebAssembly.

#[cfg(not(all(target_arch = "x86_64", target_os = "linux")))]
compile_error!("the native runtime currently requires x86-64 Linux");

#[path = "../native.rs"]
pub mod native;
#[path = "../native_gc.rs"]
mod native_gc;
