//! Runtime for statically emitted Scheme instruction streams.
//!
//! The LLVM-facing ABI passes only an opaque machine pointer and fixed-width
//! operands. No Rust layout, enum discriminant, or trait object crosses it.
//!
//! GC has three invariants: only handler entry collects; all work after that
//! safepoint is transitively GC-free; every handler publishes surviving values
//! in machine roots before returning. Never call an exported handler from
//! another handler: use the internal GC-free operations instead.

mod heap;
mod host;
mod primitives;
mod value;
mod vm;

pub use heap::SnailSchemeObject;
pub use value::Value;
pub use vm::{STOP, Vm};

use heap::Object;
use std::panic::{AssertUnwindSafe, catch_unwind};

/// Keeps Rust errors and unexpected unwinds on the Rust side of the boundary.
/// Pointers are provided by the generated program and must name its live VM.
unsafe fn handler<T: Copy>(
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
    let outcome = catch_unwind(AssertUnwindSafe(|| {
        machine.safepoint();
        operation(machine)
    }));
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

macro_rules! lexical_handler {
    ($name:ident, $operation:ident, $kind:expr) => {
        /// # Safety
        /// `machine` must point to a live VM with exclusive access for this call.
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $name(machine: *mut Vm, index: u32) {
            unsafe { handler(machine, (), |vm| vm.$operation(index, $kind)) }
        }
    };
}

lexical_handler!(snail_refer_local, refer, 0);
lexical_handler!(snail_refer_free, refer, 1);
lexical_handler!(snail_refer_global, refer, 2);
lexical_handler!(snail_constant, refer, 3);
lexical_handler!(snail_set_local, assign, 0);
lexical_handler!(snail_set_free, assign, 1);
lexical_handler!(snail_set_global, assign, 2);
lexical_handler!(snail_capture_local, capture, false);
lexical_handler!(snail_capture_free, capture, true);

/// # Safety
/// `machine` must point to a live VM with exclusive access for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_close(
    machine: *mut Vm,
    entry: u32,
    required: u32,
    has_rest: u32,
    locals: u32,
    captures: u32,
) {
    unsafe {
        handler(machine, (), |vm| {
            vm.close(entry, required, has_rest != 0, locals, captures)
        })
    }
}

/// # Safety
/// `machine` must point to a live VM with exclusive access for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_push(machine: *mut Vm) {
    unsafe { handler(machine, (), Vm::push) }
}

/// # Safety
/// `machine` must point to a live VM with exclusive access for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_call(machine: *mut Vm, argc: u32, resume: u32, tail: u32) -> u32 {
    unsafe { handler(machine, STOP, |vm| vm.call(argc, resume, tail != 0)) }
}

/// # Safety
/// `machine` must point to a live VM with exclusive access for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_return(machine: *mut Vm) -> u32 {
    unsafe { handler(machine, STOP, Vm::return_values) }
}

/// # Safety
/// `machine` must point to a live VM with exclusive access for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snail_test(machine: *mut Vm) -> u32 {
    unsafe { handler(machine, 0, |vm| Ok(u32::from(vm.single()?.is_true()))) }
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
                vm.alloc(Object::Bytevector(data.to_vec()))
            } else {
                let text = std::str::from_utf8(data).map_err(|_| "constant is not UTF-8")?;
                match kind {
                    0 => vm.alloc(Object::String(text.into())),
                    1 => vm.intern(text),
                    2 => Value::Integer(
                        text.parse()
                            .map_err(|_| "integer constant exceeds supported i64 range")?,
                    ),
                    3 => Value::Float(
                        primitives::parse_float(text).ok_or("invalid floating point constant")?,
                    ),
                    4 => Value::Char(
                        char::from_u32(text.parse().map_err(|_| "invalid character constant")?)
                            .ok_or("invalid character codepoint")?,
                    ),
                    5 => match text {
                        "0" => Value::Bool(false),
                        "1" => Value::Bool(true),
                        _ => return Err("invalid boolean constant".into()),
                    },
                    6 => Value::Nil,
                    8 => Value::Unspecified,
                    9 => Value::Eof,
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
            let value = vm.alloc(Object::Pair(vm.constant(car)?, vm.constant(cdr)?));
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
            let value = vm.alloc(Object::Vector(values));
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
