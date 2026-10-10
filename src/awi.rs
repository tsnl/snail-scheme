//! Application Wasm interface: owned roots into the engine's GC heap.
//!
//! Handles are table indices, not pointers. Each `Root` owns a distinct live
//! table slot in the current instance; dropping it releases that slot. Raw
//! handles may only cross the documented Wasm call boundary. They cannot be
//! shared between instances or threads. A fatal trap may bypass Rust cleanup;
//! discard the instance after such a failure.

use std::{marker::PhantomData, rc::Rc};

// ---- Scalar Wasm imports ----

// The native stubs let pure Rust unit tests link. AWI execution requires a
// linked Wasm instance; it does not silently substitute a native object heap.
macro_rules! imports {
    ($(fn $name:ident($($arg:ident: $ty:ty),*) $(-> $result:ty)?;)*) => {
        #[cfg(target_arch = "wasm32")]
        #[link(wasm_import_module = "snail.awi")]
        unsafe extern "C" { $(pub fn $name($($arg: $ty),*) $(-> $result)?;)* }
        $(#[cfg(not(target_arch = "wasm32"))]
        pub unsafe fn $name($($arg: $ty),*) $(-> $result)? {
            $(let _ = $arg;)*
            panic!("AWI imports require a Wasm instance");
        })*
    };
}

mod raw {
    imports! {
        fn retain(root: u32) -> u32;
        fn release(root: u32);
        fn kind(root: u32) -> u32;
        fn same(a: u32, b: u32) -> u32;
        fn call(procedure: u32, arguments: u32) -> u32;
        fn integer(value: i64) -> u32;
        fn real(value: f64) -> u32;
        fn atom(tag: u32) -> u32;
        fn pair(car: u32, cdr: u32) -> u32;
        fn vector_new(length: u32) -> u32;
        fn vector_set(root: u32, index: u32, value: u32);
        fn string_new(length: u32) -> u32;
        fn string_set(root: u32, index: u32, value: u32);
        fn extension(kind: u32, id: u32) -> u32;
        fn as_integer(root: u32) -> i64;
        fn as_real(root: u32) -> f64;
        fn atom_value(root: u32) -> u32;
        fn length(root: u32) -> u32;
        fn at(root: u32, index: u32) -> u32;
        fn char_at(root: u32, index: u32) -> u32;
        fn byte_at(root: u32, index: u32) -> u32;
        fn car(root: u32) -> u32;
        fn cdr(root: u32) -> u32;
        fn extension_kind(root: u32) -> u32;
        fn extension_id(root: u32) -> u32;
    }
}

// ---- Owned roots ----

/// Discriminants are part of AWI v0 and match `src/runtime/awi.wat`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u32)]
pub enum Kind {
    Unspecified,
    Boolean,
    Nil,
    Eof,
    Integer,
    Real,
    Character,
    Pair,
    Vector,
    String,
    Symbol,
    Bytevector,
    Procedure,
    Record,
    Extension,
    Values,
    Uninitialized,
}

impl Kind {
    fn from_raw(value: u32) -> Self {
        use Kind::*;
        const KINDS: &[Kind] = &[
            Unspecified,
            Boolean,
            Nil,
            Eof,
            Integer,
            Real,
            Character,
            Pair,
            Vector,
            String,
            Symbol,
            Bytevector,
            Procedure,
            Record,
            Extension,
            Values,
            Uninitialized,
        ];
        *KINDS.get(value as usize).expect("invalid AWI value kind")
    }
}

pub struct Root {
    handle: u32,
    instance_thread: PhantomData<Rc<()>>,
}

impl Clone for Root {
    fn clone(&self) -> Self {
        unsafe { Self::from_handle(raw::retain(self.handle)) }
    }
}

impl Drop for Root {
    fn drop(&mut self) {
        unsafe { raw::release(self.handle) }
    }
}

impl Root {
    /// Takes ownership of a distinct live root in this instance.
    ///
    /// # Safety
    /// The handle must be live, belong to this instance, and have no other
    /// owner. A borrowed argument handle must be retained before adoption.
    pub unsafe fn from_handle(handle: u32) -> Self {
        Self {
            handle,
            instance_thread: PhantomData,
        }
    }

    pub fn into_handle(self) -> u32 {
        let handle = self.handle;
        std::mem::forget(self);
        handle
    }

    pub fn kind(&self) -> Kind {
        Kind::from_raw(unsafe { raw::kind(self.handle) })
    }

    pub fn same(&self, other: &Self) -> bool {
        unsafe { raw::same(self.handle, other.handle) != 0 }
    }

    /// Calls Scheme synchronously. The call may allocate and call Rust again.
    /// Do not hold a host borrow or lock that a callback could reacquire.
    /// `Err` reports argument validation only; Scheme traps or aborts are fatal
    /// and do not become Rust errors or guarantee destructor execution.
    pub fn call(&self, values: &[Self]) -> Result<Self, String> {
        self.require(&[Kind::Procedure])?;
        let arguments = Self::vector(values);
        Ok(unsafe { Self::from_handle(raw::call(self.handle, arguments.handle)) })
    }

    fn require(&self, kinds: &[Kind]) -> Result<(), String> {
        let found = self.kind();
        if kinds.contains(&found) {
            Ok(())
        } else {
            Err(format!("expected {kinds:?}, found {found:?}"))
        }
    }

    fn index(&self, index: usize) -> Result<u32, String> {
        if index < self.len()? {
            Ok(index as u32)
        } else {
            Err("index out of range".into())
        }
    }

    // ---- Construction ----

    pub fn integer(value: i64) -> Self {
        unsafe { Self::from_handle(raw::integer(value)) }
    }

    pub fn real(value: f64) -> Self {
        unsafe { Self::from_handle(raw::real(value)) }
    }

    fn atom(tag: u32) -> Self {
        unsafe { Self::from_handle(raw::atom(tag)) }
    }

    pub fn boolean(value: bool) -> Self {
        Self::atom(u32::from(value))
    }
    pub fn nil() -> Self {
        Self::atom(2)
    }
    pub fn unspecified() -> Self {
        Self::atom(3)
    }
    pub fn eof() -> Self {
        Self::atom(4)
    }
    pub fn character(value: char) -> Self {
        Self::atom(value as u32 + 256)
    }

    pub fn pair(car: &Self, cdr: &Self) -> Self {
        unsafe { Self::from_handle(raw::pair(car.handle, cdr.handle)) }
    }

    pub fn vector(values: &[Self]) -> Self {
        let length = u32::try_from(values.len()).expect("AWI vector too long");
        let root = unsafe { Self::from_handle(raw::vector_new(length)) };
        for (index, value) in values.iter().enumerate() {
            unsafe { raw::vector_set(root.handle, index as u32, value.handle) };
        }
        root
    }

    pub fn string(text: &str) -> Self {
        let length = u32::try_from(text.chars().count()).expect("AWI string too long");
        let root = unsafe { Self::from_handle(raw::string_new(length)) };
        for (index, ch) in text.chars().enumerate() {
            unsafe { raw::string_set(root.handle, index as u32, ch as u32) };
        }
        root
    }

    /// Creates the unique GC owner of an external resource.
    ///
    /// # Safety
    /// `(kind, id)` must identify a live resource with a matching host cleanup
    /// implementation. No other independently finalized wrapper may own it.
    /// Clone this root to share the wrapper, rather than constructing it again.
    pub unsafe fn from_raw_extension(kind: u32, id: u32) -> Self {
        unsafe { Self::from_handle(raw::extension(kind, id)) }
    }

    // ---- Checked access ----

    pub fn as_integer(&self) -> Result<i64, String> {
        self.require(&[Kind::Integer])?;
        Ok(unsafe { raw::as_integer(self.handle) })
    }

    pub fn as_real(&self) -> Result<f64, String> {
        self.require(&[Kind::Integer, Kind::Real])?;
        Ok(unsafe { raw::as_real(self.handle) })
    }

    pub fn as_bool(&self) -> Result<bool, String> {
        self.require(&[Kind::Boolean])?;
        Ok(unsafe { raw::atom_value(self.handle) } == 1)
    }

    pub fn as_character(&self) -> Result<char, String> {
        self.require(&[Kind::Character])?;
        char::from_u32(unsafe { raw::atom_value(self.handle) } - 256)
            .ok_or_else(|| "invalid character".into())
    }

    pub fn len(&self) -> Result<usize, String> {
        self.require(&[
            Kind::Vector,
            Kind::Values,
            Kind::String,
            Kind::Symbol,
            Kind::Bytevector,
        ])?;
        Ok(unsafe { raw::length(self.handle) } as usize)
    }

    pub fn is_empty(&self) -> Result<bool, String> {
        Ok(self.len()? == 0)
    }

    pub fn at(&self, index: usize) -> Result<Self, String> {
        self.require(&[Kind::Vector, Kind::Values])?;
        let index = self.index(index)?;
        Ok(unsafe { Self::from_handle(raw::at(self.handle, index)) })
    }

    pub fn car(&self) -> Result<Self, String> {
        self.require(&[Kind::Pair])?;
        Ok(unsafe { Self::from_handle(raw::car(self.handle)) })
    }

    pub fn cdr(&self) -> Result<Self, String> {
        self.require(&[Kind::Pair])?;
        Ok(unsafe { Self::from_handle(raw::cdr(self.handle)) })
    }

    pub fn char_at(&self, index: usize) -> Result<char, String> {
        self.require(&[Kind::String, Kind::Symbol])?;
        let index = self.index(index)?;
        char::from_u32(unsafe { raw::char_at(self.handle, index) })
            .ok_or_else(|| "invalid character".into())
    }

    pub fn byte_at(&self, index: usize) -> Result<u8, String> {
        self.require(&[Kind::Bytevector])?;
        let index = self.index(index)?;
        Ok(unsafe { raw::byte_at(self.handle, index) } as u8)
    }

    pub fn text(&self) -> Result<String, String> {
        self.require(&[Kind::String, Kind::Symbol])?;
        (0..self.len()?).map(|index| self.char_at(index)).collect()
    }

    pub fn extension_parts(&self) -> Result<(u32, u32), String> {
        self.require(&[Kind::Extension])?;
        Ok(unsafe {
            (
                raw::extension_kind(self.handle),
                raw::extension_id(self.handle),
            )
        })
    }
}

// ---- Borrowed call arguments ----

pub struct Arguments {
    handle: u32,
    instance_thread: PhantomData<Rc<()>>,
}

impl Arguments {
    /// # Safety
    /// `handle` must denote a vector rooted by the caller for the lifetime of
    /// this object. This borrow must not escape the exported function call.
    pub unsafe fn borrow(handle: u32) -> Self {
        Self {
            handle,
            instance_thread: PhantomData,
        }
    }

    pub fn len(&self) -> usize {
        unsafe { raw::length(self.handle) as usize }
    }
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn get(&self, index: usize) -> Result<Root, String> {
        if index >= self.len() {
            return Err("argument index out of range".into());
        }
        Ok(unsafe { Root::from_handle(raw::at(self.handle, index as u32)) })
    }

    pub fn check(&self, name: &str, min: usize, max: usize) -> Result<(), String> {
        let count = self.len();
        if (min..=max).contains(&count) {
            Ok(())
        } else {
            Err(format!(
                "{name}: expected {min}..={max} arguments, got {count}"
            ))
        }
    }
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn value_kind_discriminants_match_the_wire_contract() {
        assert_eq!(Kind::from_raw(0), Kind::Unspecified);
        assert_eq!(Kind::from_raw(4), Kind::Integer);
        assert_eq!(Kind::from_raw(14), Kind::Extension);
        assert_eq!(Kind::from_raw(16), Kind::Uninitialized);
    }
}
