//! Experimental Rust implementation of the compiler's numeric VM instructions.
//! Rust 1.95 warns that export inline attributes are ignored, but emits LLVM
//! alwaysinline for them; the experiment audits the linked artifact explicitly.
#![allow(unused_attributes)]

//! The signatures and state transitions match llvm.sld's optional LLVM bodies.

use crate::{State, Value, Vm, snail_rt_numeric};

// ---- Numeric transitions ----

#[derive(Clone, Copy)]
enum Operation {
    Add,
    Subtract,
    Equal,
    Less,
    LessEqual,
    Greater,
    GreaterEqual,
}

#[inline(always)]
fn fixnum_result(operation: Operation, left: Value, right: Value) -> Option<Value> {
    let (left, right) = (left.bits() as i32, right.bits() as i32);
    if left & right & 1 == 0 {
        return None;
    }
    match operation {
        Operation::Add => Value::fixnum(((left >> 1) + (right >> 1)) as i64),
        Operation::Subtract => Value::fixnum(((left >> 1) - (right >> 1)) as i64),
        Operation::Equal => Some(Value::boolean(left == right)),
        Operation::Less => Some(Value::boolean(left < right)),
        Operation::LessEqual => Some(Value::boolean(left <= right)),
        Operation::Greater => Some(Value::boolean(left > right)),
        Operation::GreaterEqual => Some(Value::boolean(left >= right)),
    }
}

// Both pointers name the same VM allocation. Keep them raw: overlapping mutable
// references would incorrectly promise no aliasing to LLVM. No stack pointer or
// borrowed state survives the fallback's allocation/collection boundary.
#[inline(always)]
unsafe fn numeric(machine: *mut Vm, state: *mut State, global: u32, operation: Operation) -> bool {
    unsafe {
        let top = (*state).s;
        let end = (*state).stack_end;
        let left = *end.sub((top - 1) as usize);
        let right = *end.sub(top as usize);
        if let Some(answer) = fixnum_result(operation, left, right) {
            (*state).a = answer;
            (*state).result_count = 1;
            (*state).s = top - 2;
            return true;
        }
        // Keep operands published through s and preserve f/c; the service roots
        // a/c and polls before borrowing arguments, then publishes its result.
        fallback(machine, state, global)
    }
}

#[inline(never)]
unsafe fn fallback(machine: *mut Vm, state: *mut State, global: u32) -> bool {
    unsafe {
        snail_rt_numeric(machine, global);
        (*state).stopped == 0
    }
}

// ---- Compiler entry points ----

// Each entry requires a live exclusively accessible VM, its own register record,
// two published stack operands, and the matching immutable numeric global.
// Rust bool uses the LLVM i1 result expected by the generated instruction calls.

#[unsafe(export_name = "snail_vm_add")]
#[inline(always)]
unsafe extern "C" fn add(machine: *mut Vm, state: *mut State, global: u32) -> bool {
    unsafe { numeric(machine, state, global, Operation::Add) }
}

#[unsafe(export_name = "snail_vm_subtract")]
#[inline(always)]
unsafe extern "C" fn subtract(machine: *mut Vm, state: *mut State, global: u32) -> bool {
    unsafe { numeric(machine, state, global, Operation::Subtract) }
}

#[unsafe(export_name = "snail_vm_numeric-equal")]
#[inline(always)]
unsafe extern "C" fn equal(machine: *mut Vm, state: *mut State, global: u32) -> bool {
    unsafe { numeric(machine, state, global, Operation::Equal) }
}

#[unsafe(export_name = "snail_vm_less")]
#[inline(always)]
unsafe extern "C" fn less(machine: *mut Vm, state: *mut State, global: u32) -> bool {
    unsafe { numeric(machine, state, global, Operation::Less) }
}

#[unsafe(export_name = "snail_vm_less-equal")]
#[inline(always)]
unsafe extern "C" fn less_equal(machine: *mut Vm, state: *mut State, global: u32) -> bool {
    unsafe { numeric(machine, state, global, Operation::LessEqual) }
}

#[unsafe(export_name = "snail_vm_greater")]
#[inline(always)]
unsafe extern "C" fn greater(machine: *mut Vm, state: *mut State, global: u32) -> bool {
    unsafe { numeric(machine, state, global, Operation::Greater) }
}

#[unsafe(export_name = "snail_vm_greater-equal")]
#[inline(always)]
unsafe extern "C" fn greater_equal(machine: *mut Vm, state: *mut State, global: u32) -> bool {
    unsafe { numeric(machine, state, global, Operation::GreaterEqual) }
}
