//! Runtime for statically emitted Scheme instruction streams.
//!
//! The LLVM-facing ABI passes only an opaque machine pointer and fixed-width
//! operands, plus transient pointers to tagged-word slots. No Rust container
//! layout, enum discriminant, or trait object crosses it.
//!
//! Instruction entry is the automatic GC safepoint. Slot services below are
//! GC-free; generated code publishes surviving values before the next entry.
//! Explicit Scheme collection runs only inside the VM's rooted dispatch loop.

mod host;
mod object;
mod primitives;

mod vm;

pub use object::{GcStatistics, SnailSchemeObject, Value};

pub use vm::{STOP, Vm};

/// Version of the generated-code protocol, including tagged singleton values.
/// Keep this in sync with `write-llvm-program` in `llvm.sld`.
pub const PROGRAM_ABI: u32 = 1;

use object::*;
use std::panic::{AssertUnwindSafe, catch_unwind};

/// Keeps Rust errors and unexpected unwinds on the Rust side of the boundary.
/// Pointers are provided by the generated program and must name its live VM.
unsafe fn boundary<T: Copy>(
    machine: *mut Vm,
    stopped: T,
    operation: impl FnOnce(&mut Vm) -> Result<T, String>,
) -> T {
    let Some(machine) = (unsafe { machine.as_mut() }) else {
        return stopped;
    };
    if machine.is_halted() {
        return stopped;
    }
    let outcome = catch_unwind(AssertUnwindSafe(|| operation(machine)));
    match outcome {
        Ok(Ok(value)) => value,
        Ok(Err(error)) => {
            machine.fail(error);
            stopped
        }
        Err(_) => {
            machine.fail("internal Rust runtime panic".into());
            stopped
        }
    }
}

/// Startup constructors and instruction entry may collect before doing any work.
unsafe fn handler<T: Copy>(
    machine: *mut Vm,
    stopped: T,
    operation: impl FnOnce(&mut Vm) -> Result<T, String>,
) -> T {
    unsafe {
        boundary(machine, stopped, |vm| {
            vm.safepoint();
            operation(vm)
        })
    }
}

// ---- Slot and control services for Scheme-written LLVM instructions ----

// Slot pointers last until the next operation that can relocate that storage.
// These accessors never collect. LLVM loads a source before requesting a new
// result/operand slot, and publishes the word before another instruction enters.

/// # Safety
/// `machine` must name a live, exclusively accessible VM with all values rooted.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_rt_enter(machine: *mut Vm) -> u32 {
    unsafe { handler(machine, 0, |_| Ok(1)) }
}

/// # Safety
/// `machine` must name a live VM; consume the returned slot before resizing it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_rt_slot(machine: *mut Vm, index: u32, kind: u32) -> *mut Value {
    unsafe { boundary(machine, std::ptr::null_mut(), |vm| vm.slot(index, kind)) }
}

/// # Safety
/// `machine` must name a live VM; consume the returned slot before resizing it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_rt_capture_slot(
    machine: *mut Vm,
    index: u32,
    free: u32,
) -> *mut Value {
    unsafe {
        boundary(machine, std::ptr::null_mut(), |vm| {
            vm.capture_slot(index, free != 0)
        })
    }
}

/// # Safety
/// `machine` must name a live VM; consume the returned slot before replacing results.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_rt_single(machine: *mut Vm) -> *mut Value {
    unsafe { boundary(machine, std::ptr::null_mut(), Vm::single_slot) }
}

/// # Safety
/// `machine` must name a live VM; fill the returned slot before another safepoint.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_rt_result(machine: *mut Vm) -> *mut Value {
    unsafe { boundary(machine, std::ptr::null_mut(), |vm| Ok(vm.result_slot())) }
}

/// # Safety
/// `machine` must name a live VM; fill the returned slot before another safepoint.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_rt_push(machine: *mut Vm) -> *mut Value {
    unsafe { boundary(machine, std::ptr::null_mut(), |vm| Ok(vm.push_slot())) }
}

/// # Safety
/// `machine` must point to a live VM with exclusive access for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_rt_uninitialized(machine: *mut Vm) {
    unsafe {
        boundary(machine, (), |_| {
            Err("read of an uninitialized binding".into())
        })
    }
}

/// # Safety
/// `machine` must point to a live VM with exclusive access for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_rt_close(
    machine: *mut Vm,
    entry: u32,
    required: u32,
    has_rest: u32,
    locals: u32,
    captures: u32,
) {
    unsafe {
        boundary(machine, (), |vm| {
            vm.close(entry, required, has_rest != 0, locals, captures)
        })
    }
}

/// # Safety
/// `machine` must point to a live VM with all surviving values published in roots.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_rt_call(machine: *mut Vm, argc: u32, resume: u32, tail: u32) -> u32 {
    unsafe { boundary(machine, STOP, |vm| vm.call(argc, resume, tail != 0)) }
}

/// # Safety
/// `machine` must point to a live VM with all surviving values published in roots.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_rt_return(machine: *mut Vm) -> u32 {
    unsafe { boundary(machine, STOP, Vm::return_values) }
}

/// # Safety
/// `machine` must point to a live VM with exclusive access for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_halt(machine: *mut Vm) {
    unsafe {
        handler(machine, (), |vm| {
            vm.halt();
            Ok(())
        })
    }
}

/// # Safety
/// `machine` must point to a live VM with exclusive access for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_invalid_pc(machine: *mut Vm, pc: u32) {
    unsafe {
        handler(machine, (), |_| {
            Err(format!("invalid VM instruction address: {pc}"))
        })
    }
}

unsafe fn bytes<'a>(data: *const u8, len: u32) -> Result<&'a [u8], String> {
    if len == 0 {
        return Ok(&[]);
    }
    if data.is_null() {
        return Err("null constant data pointer".into());
    }
    Ok(unsafe { std::slice::from_raw_parts(data, len as usize) })
}

/// # Safety
/// `machine` must be live and exclusively accessible. Nonempty `data` must name
/// `len` readable bytes and must not overlap mutable machine storage.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_const_atom(
    machine: *mut Vm,
    index: u32,
    kind: u32,
    data: *const u8,
    len: u32,
) {
    unsafe {
        handler(machine, (), |vm| {
            let data = bytes(data, len)?;
            let value = if kind == 7 {
                vm.alloc(Bytevector(data.to_vec()))
            } else {
                let text = std::str::from_utf8(data).map_err(|_| "constant is not UTF-8")?;
                match kind {
                    0 => vm.alloc(Text(text.into())),
                    1 => vm.intern(text),
                    2 => vm.integer(
                        text.parse()
                            .map_err(|_| "integer constant exceeds supported i64 range")?,
                    ),
                    3 => vm.float(
                        primitives::parse_float(text).ok_or("invalid floating point constant")?,
                    ),
                    4 => Value::character(
                        char::from_u32(text.parse().map_err(|_| "invalid character constant")?)
                            .ok_or("invalid character codepoint")?,
                    ),
                    5 => match text {
                        "0" => Value::boolean(false),
                        "1" => Value::boolean(true),
                        _ => return Err("invalid boolean constant".into()),
                    },
                    6 => Value::NIL,
                    8 => Value::UNSPECIFIED,
                    9 => Value::EOF,
                    _ => return Err("unknown constant kind".into()),
                }
            };
            vm.set_constant(index, value)
        })
    }
}

/// # Safety
/// `machine` must point to a live VM with exclusive access for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_const_pair(machine: *mut Vm, index: u32, car: u32, cdr: u32) {
    unsafe {
        handler(machine, (), |vm| {
            let value = vm.alloc(Pair(vm.constant(car)?, vm.constant(cdr)?));
            vm.set_constant(index, value)
        })
    }
}

/// # Safety
/// `machine` must be live and exclusively accessible. Nonempty `indices` must
/// name `count` aligned readable u32s outside mutable machine storage.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_const_vector(
    machine: *mut Vm,
    index: u32,
    indices: *const u32,
    count: u32,
) {
    unsafe {
        handler(machine, (), |vm| {
            let indices = if count == 0 {
                &[]
            } else {
                if indices.is_null() {
                    return Err("null vector constant pointer".into());
                }
                std::slice::from_raw_parts(indices, count as usize)
            };
            let values = indices
                .iter()
                .map(|index| vm.constant(*index))
                .collect::<Result<Vec<_>, _>>()?;
            let value = vm.alloc(Vector(values));
            vm.set_constant(index, value)
        })
    }
}

/// # Safety
/// `machine` must be live and exclusively accessible. Nonempty `name` must name
/// `len` readable bytes and must not overlap mutable machine storage.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_global_primitive(
    machine: *mut Vm,
    index: u32,
    name: *const u8,
    len: u32,
) {
    unsafe {
        handler(machine, (), |vm| {
            let name = std::str::from_utf8(bytes(name, len)?)
                .map_err(|_| "primitive name is not UTF-8")?;
            vm.global_primitive(index, name.into())
        })
    }
}
