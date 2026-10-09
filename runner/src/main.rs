use snail_runtime::Vm;
use std::ffi::c_void;

unsafe extern "C" {
    fn snail_global_count() -> u32;
    fn snail_constant_count() -> u32;
    fn snail_program(machine: *mut c_void);
}

fn main() {
    // Only opaque pointers and fixed-width scalar values cross this boundary.
    let mut machine = unsafe {
        Vm::new(
            snail_global_count(),
            snail_constant_count(),
            std::env::args().collect(),
        )
    };
    unsafe {
        snail_program((&mut machine as *mut Vm).cast());
    }
    if let Some(error) = machine.error() {
        eprintln!("snail-scheme: {error}");
    }
    std::process::exit(machine.exit_code());
}
