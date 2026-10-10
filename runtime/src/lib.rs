//! Runtime for statically emitted Scheme instruction streams.
//!
//! The LLVM-facing ABI passes only an opaque machine pointer and fixed-width
//! operands, a fixed register record, and transient pointers to tagged-word slots.
//! No Rust container layout, enum discriminant, or trait object crosses it.
//!
//! Only allocating operations are automatic GC boundaries. They collect before
//! acquiring an owned allocation capability; allocations within Rust never collect.
//! Generated code publishes live words before invoking such an operation.
//!
//! Every unsafe ABI call requires all Scheme words in VM slots to be immediates
//! or live objects owned by that VM. A stale or foreign pointer is invalid even
//! when its bits name mapped memory. Slot pointers and the VM itself must obey
//! the exclusive access/lifetime contracts below; forged values are unsupported.

mod host;
mod object;
mod primitives;
mod representation;

mod vm;

pub use object::{Extension, ExtensionVTable, GcStatistics, GcVisit, Value};

pub use vm::{CONSUME, STOP, State, Vm};

/// Version of the generated-code protocol, including tagged singleton values.
/// Keep this in sync with `write-mir-library-as-llvm` in `llvm.sld`.
pub const PROGRAM_ABI: u32 = 3;

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

// ---- Slot and control services for generated code ----

// The register record remains at a fixed address while its VM stays in place.
// Stack-slot pointers last until a service can resize the stack. LLVM loads
// sources before resizing a destination and publishes live words before a
// safepoint. Raw VM and register pointers may alias; neither has a noalias promise.

/// # Safety
/// `machine` must name a live, exclusively accessible VM with all values rooted.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_rt_state(machine: *mut Vm) -> *mut State {
    unsafe { boundary(machine, std::ptr::null_mut(), |vm| Ok(vm.state())) }
}

/// # Safety
/// `machine` must name a live VM with all surviving values published in roots.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_rt_reserve(machine: *mut Vm, depth: u32) {
    unsafe { boundary(machine, (), |vm| vm.reserve(depth)) }
}

/// # Safety
/// `machine` must name a live VM with all surviving values published in roots.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_rt_box(machine: *mut Vm, index: u32) {
    unsafe { boundary(machine, (), |vm| vm.box_local(index)) }
}

/// # Safety
/// `machine` must name a live VM and `cell` must be one of its live values.
/// Consume the returned slot before a service that can collect its cell.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_rt_cell(machine: *mut Vm, cell: Value) -> *mut Value {
    unsafe { boundary(machine, std::ptr::null_mut(), |vm| vm.cell_slot(cell)) }
}

/// # Safety
/// `machine` must name a live VM with its active closure rooted.
/// Consume the returned slot before a service that can collect its closure.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_rt_free(machine: *mut Vm, index: u32) -> *mut Value {
    unsafe { boundary(machine, std::ptr::null_mut(), |vm| vm.free_slot(index)) }
}

/// # Safety
/// `machine` must point to a live VM with exclusive access for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_rt_value_error(machine: *mut Vm) {
    unsafe { boundary(machine, (), |vm| vm.single().map(|_| ())) }
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
pub unsafe extern "C" fn snail_rt_prepare_apply(machine: *mut Vm, argc: u32) -> u32 {
    unsafe { boundary(machine, 255, |vm| vm.prepare_apply(argc)) }
}

/// # Safety
/// `machine` must name a live, exclusively accessible VM. Its top two stack
/// words and registers must be rooted; `global` must identify a numeric builtin.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_rt_numeric(machine: *mut Vm, global: u32) {
    unsafe { boundary(machine, (), |vm| vm.numeric(global)) }
}

/// # Safety
/// `machine` must point to a live VM with all surviving values published in roots.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_rt_receive(machine: *mut Vm) {
    unsafe { boundary(machine, (), Vm::receive) }
}

/// # Safety
/// `machine` must point to a live VM with all surviving values published in roots.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_rt_capture(machine: *mut Vm) {
    unsafe { boundary(machine, (), Vm::capture) }
}

/// # Safety
/// `machine` must point to a live VM with all surviving values published in roots.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_rt_restore(machine: *mut Vm, argc: u32) {
    unsafe { boundary(machine, (), |vm| vm.restore(argc)) }
}

/// # Safety
/// `machine` must point to a live VM with exclusive access for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_halt(machine: *mut Vm) {
    unsafe {
        boundary(machine, (), |vm| {
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
        boundary(machine, (), |_| {
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
        boundary(machine, (), |vm| {
            let data = bytes(data, len)?;
            let mut allocation = vm.allocation([]);
            let value = if kind == 7 {
                allocation.alloc(Bytevector(data.to_vec()))
            } else {
                let text = std::str::from_utf8(data).map_err(|_| "constant is not UTF-8")?;
                match kind {
                    0 => allocation.alloc(Text::new(text.into())),
                    1 => allocation.intern(text),
                    2 => allocation.integer(
                        text.parse()
                            .map_err(|_| "integer constant exceeds supported i64 range")?,
                    ),
                    3 => allocation.float(
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
        boundary(machine, (), |vm| {
            let pair = Pair(vm.constant(car)?, vm.constant(cdr)?);
            let value = vm.allocation([]).alloc(pair);
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
        boundary(machine, (), |vm| {
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
            let value = vm.allocation([]).alloc(Vector(values));
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
        boundary(machine, (), |vm| {
            let name = std::str::from_utf8(bytes(name, len)?)
                .map_err(|_| "primitive name is not UTF-8")?;
            vm.global_primitive(index, name.into())
        })
    }
}
