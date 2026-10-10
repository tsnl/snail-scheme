//! Leaf operations called explicitly by MIR. None allocates or collects.
//! Bit conversions are total; a meaningful fixnum encode/decode requires the
//! caller to establish signed31 range/tag preconditions in surrounding MIR.

use crate::object::{ObjectKind, object_kind};
use snail_abi::export;

// ---- Tagged words ----

#[export("snail_value_is_fixnum")]
#[inline(always)]
fn is_fixnum(word: u32) -> u32 {
    word & 1
}

#[export("snail_value_to_i32")]
#[inline(always)]
fn to_i32(word: u32) -> i32 {
    (word as i32) >> 1
}

#[export("snail_value_from_i32")]
#[inline(always)]
fn from_i32(integer: i32) -> u32 {
    (integer as u32).wrapping_shl(1) | 1
}

#[export("snail_value_from_boolean")]
#[inline(always)]
fn from_boolean(boolean: u32) -> u32 {
    crate::Value::boolean(boolean != 0).bits() as u32
}

// ---- Machine integers ----

// All operations are total on 32-bit words. Shifts mask their count modulo 32.

#[export("snail_i32_identity")]
#[inline(always)]
fn i32_identity(word: u32) -> u32 {
    word
}

#[export("snail_i32_add")]
#[inline(always)]
fn i32_add(left: u32, right: u32) -> u32 {
    left.wrapping_add(right)
}

#[export("snail_i32_sub")]
#[inline(always)]
fn i32_sub(left: u32, right: u32) -> u32 {
    left.wrapping_sub(right)
}

#[export("snail_i32_mul")]
#[inline(always)]
fn i32_mul(left: u32, right: u32) -> u32 {
    left.wrapping_mul(right)
}

#[export("snail_i32_and")]
#[inline(always)]
fn i32_and(left: u32, right: u32) -> u32 {
    left & right
}

#[export("snail_i32_or")]
#[inline(always)]
fn i32_or(left: u32, right: u32) -> u32 {
    left | right
}

#[export("snail_i32_xor")]
#[inline(always)]
fn i32_xor(left: u32, right: u32) -> u32 {
    left ^ right
}

#[export("snail_i32_shl")]
#[inline(always)]
fn i32_shl(left: u32, right: u32) -> u32 {
    left.wrapping_shl(right)
}

#[export("snail_i32_lshr")]
#[inline(always)]
fn i32_lshr(left: u32, right: u32) -> u32 {
    left.wrapping_shr(right)
}

#[export("snail_i32_ashr")]
#[inline(always)]
fn i32_ashr(left: u32, right: u32) -> u32 {
    (left as i32).wrapping_shr(right) as u32
}

#[export("snail_i32_eq")]
#[inline(always)]
fn i32_eq(left: u32, right: u32) -> u32 {
    u32::from(left == right)
}

#[export("snail_i32_ne")]
#[inline(always)]
fn i32_ne(left: u32, right: u32) -> u32 {
    u32::from(left != right)
}

#[export("snail_i32_ugt")]
#[inline(always)]
fn i32_ugt(left: u32, right: u32) -> u32 {
    u32::from(left > right)
}

#[export("snail_i32_uge")]
#[inline(always)]
fn i32_uge(left: u32, right: u32) -> u32 {
    u32::from(left >= right)
}

#[export("snail_i32_ult")]
#[inline(always)]
fn i32_ult(left: u32, right: u32) -> u32 {
    u32::from(left < right)
}

#[export("snail_i32_ule")]
#[inline(always)]
fn i32_ule(left: u32, right: u32) -> u32 {
    u32::from(left <= right)
}

#[export("snail_i32_sgt")]
#[inline(always)]
fn i32_sgt(left: u32, right: u32) -> u32 {
    u32::from((left as i32) > (right as i32))
}

#[export("snail_i32_sge")]
#[inline(always)]
fn i32_sge(left: u32, right: u32) -> u32 {
    u32::from((left as i32) >= (right as i32))
}

#[export("snail_i32_slt")]
#[inline(always)]
fn i32_slt(left: u32, right: u32) -> u32 {
    u32::from((left as i32) < (right as i32))
}

#[export("snail_i32_sle")]
#[inline(always)]
fn i32_sle(left: u32, right: u32) -> u32 {
    u32::from((left as i32) <= (right as i32))
}

// ---- Pointer arithmetic ----

// Exposed provenance matches the runtime's existing tagged-word representation.
#[allow(unused_attributes)]
#[unsafe(no_mangle)]
#[inline(always)]
pub extern "C" fn snail_pointer_offset(pointer: *mut u8, bytes: i32) -> *mut u8 {
    pointer.wrapping_offset(bytes as isize)
}

#[allow(unused_attributes)]
#[unsafe(no_mangle)]
#[inline(always)]
pub extern "C" fn snail_pointer_to_i32(pointer: *mut u8) -> u32 {
    pointer.expose_provenance() as u32
}

#[allow(unused_attributes)]
#[unsafe(no_mangle)]
#[inline(always)]
pub extern "C" fn snail_i32_to_pointer(word: u32) -> *mut u8 {
    std::ptr::with_exposed_provenance_mut(word as usize)
}

// ---- Heap predicates ----

// These read an object's immutable kind; they are not memory-independent.
// Every input must be an immediate or a live object word from the current VM.

#[export("snail_value_is_procedure")]
#[inline(always)]
unsafe fn is_procedure(word: u32) -> u32 {
    u32::from(matches!(
        unsafe { object_kind(word) },
        Some(ObjectKind::Closure | ObjectKind::Primitive | ObjectKind::Continuation)
    ))
}

#[export("snail_value_is_number")]
#[inline(always)]
unsafe fn is_number(word: u32) -> u32 {
    u32::from(
        is_fixnum(word) != 0
            || matches!(
                unsafe { object_kind(word) },
                Some(ObjectKind::Integer | ObjectKind::Float)
            ),
    )
}

#[export("snail_value_is_exact_integer")]
#[inline(always)]
unsafe fn is_exact_integer(word: u32) -> u32 {
    u32::from(is_fixnum(word) != 0 || unsafe { object_kind(word) } == Some(ObjectKind::Integer))
}

// ---- Foreign call fixture ----

#[export("snail_foreign_add_i32")]
fn add(left: i32, right: i32) -> i32 {
    left.wrapping_add(right)
}

#[export("snail_foreign_subtract_i32")]
fn subtract(left: i32, right: i32) -> i32 {
    left.wrapping_sub(right)
}

/// Supplies opaque C function pointers for the MIR direct/indirect-call fixture.
/// The selection stays opaque under LTO so the fixture exercises call_indirect.
#[unsafe(no_mangle)]
pub extern "C" fn snail_foreign_select_i32(selector: u32) -> extern "C" fn(i32, i32) -> i32 {
    if std::hint::black_box(selector) == 0 {
        __snail_export_add
    } else {
        __snail_export_subtract
    }
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Value, object::*, vm::Runtime};

    #[test]
    fn bit_conversions_cover_signed31_boundaries_and_noncanonical_inputs() {
        for integer in [-(1 << 30), -1, 0, 1, (1 << 30) - 1] {
            let word = from_i32(integer);
            assert_eq!(word, Value::fixnum(integer as i64).unwrap().bits() as u32);
            assert_eq!(is_fixnum(word), 1);
            assert_eq!(to_i32(word), integer);
        }
        assert_eq!(from_i32(i32::MAX), u32::MAX);
        assert_eq!(to_i32(u32::MAX - 1), -1);
        assert_eq!(from_boolean(0), Value::FALSE.bits() as u32);
        assert_eq!(from_boolean(u32::MAX), Value::TRUE.bits() as u32);
    }

    #[test]
    fn predicates_read_live_boxed_kinds_without_allocating() {
        let mut runtime = Runtime::for_test(Vec::new());
        let mut allocation = runtime.allocation();
        let integer = allocation.alloc(Integer(i64::MAX)).bits() as u32;
        let float = allocation.alloc(Float(0.5)).bits() as u32;
        let pair = allocation.alloc(Pair(Value::NIL, Value::NIL)).bits() as u32;
        unsafe {
            assert_eq!(is_number(integer), 1);
            assert_eq!(is_number(float), 1);
            assert_eq!(is_number(pair), 0);
            assert_eq!(is_exact_integer(integer), 1);
            assert_eq!(is_exact_integer(float), 0);
            assert_eq!(is_procedure(pair), 0);
            assert_eq!(is_procedure(Value::FALSE.bits() as u32), 0);
        }
    }

    #[test]
    fn exported_functions_work_through_opaque_c_pointers() {
        assert_eq!(__snail_export_add(20, 22), 42);
        assert_eq!(snail_foreign_select_i32(0)(20, 22), 42);
        assert_eq!(snail_foreign_select_i32(1)(20, 22), -2);
    }

    #[test]
    fn machine_operations_are_total_at_wrapping_and_signed_boundaries() {
        assert_eq!(i32_add(u32::MAX, 1), 0);
        assert_eq!(i32_sub(0, 1), u32::MAX);
        assert_eq!(i32_mul(u32::MAX, 2), u32::MAX - 1);
        assert_eq!(i32_shl(1, 33), 2);
        assert_eq!(i32_lshr(u32::MAX, 31), 1);
        assert_eq!(i32_ashr(u32::MAX, 63), u32::MAX);
        assert_eq!(i32_slt(u32::MAX, 0), 1);
        assert_eq!(i32_ult(u32::MAX, 0), 0);
    }

    #[test]
    fn pointer_conversion_preserves_exposed_provenance_and_byte_offsets() {
        let mut bytes = [1u8, 2, 3];
        let start = bytes.as_mut_ptr();
        let next = snail_pointer_offset(start, 1);
        let restored = snail_i32_to_pointer(snail_pointer_to_i32(next));
        assert_eq!(unsafe { *restored }, 2);
        assert_eq!(snail_pointer_offset(restored, -1), start);
    }
}
