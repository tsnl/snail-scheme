use snail_runtime::{PROGRAM_ABI, Vm};
use std::{ffi::c_void, time::Instant};

unsafe extern "C" {
    fn snail_program_abi() -> u32;
    fn snail_global_count() -> u32;
    fn snail_constant_count() -> u32;
    fn snail_program(machine: *mut c_void);
}

fn main() {
    let started = Instant::now();
    check_program_abi();
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
    if std::env::var_os("SNAIL_RUNTIME_STATS").is_some() {
        report_statistics(&machine, started);
    }
    std::process::exit(machine.exit_code());
}

fn check_program_abi() {
    let actual = unsafe { snail_program_abi() };
    if actual != PROGRAM_ABI {
        eprintln!("snail-scheme: program ABI {actual} does not match runtime ABI {PROGRAM_ABI}");
        std::process::exit(1);
    }
}

fn report_statistics(machine: &Vm, started: Instant) {
    let gc = machine.gc_statistics();
    eprintln!(
        "runtime: elapsed_ns={} gc_collections={} gc_ns={} gc_max_ns={} allocated={} reclaimed={} live={} peak={} max_frames={}",
        started.elapsed().as_nanos(),
        gc.collections,
        gc.total_nanoseconds,
        gc.max_nanoseconds,
        gc.allocated,
        gc.reclaimed,
        gc.live,
        gc.peak,
        machine.max_frames()
    );
}
