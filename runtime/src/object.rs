//! v3's tagged values and fixed object fields, with Rust-owned storage.
//!
//! The tags and the existing object-kind numbers come from `origin/v3`'s
//! `inc/ss-core/object.0.hh`. Pairs contain car/cdr, boxes contain one word,
//! strings contain byte count/pointer/ownership, and vectors own an array.
//! Rust replaces the C++ virtual destructor and allocator bookkeeping with a
//! small kind/mark header. Only foreign extension objects have a virtual table.
//!
//! Allocation never collects. The VM publishes roots before starting a Rust
//! operation and allows no collection until that operation returns. Every heap
//! accessor therefore requires a live value from this heap; keeping an unrooted
//! word across collection violates the runtime's internal lifetime invariant.

use crate::{host::Port, vm::HeapAccess};
use std::{ffi::c_void, ptr::NonNull};

#[cfg(not(target_pointer_width = "32"))]
compile_error!("the Snail-Scheme object ABI requires a 32-bit target");

// ---- Tagged words ----

#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
#[repr(transparent)]
pub struct Value(usize);

impl Value {
    pub const FALSE_BITS: usize = 20;
    pub const UNSPECIFIED_BITS: usize = 36;
    pub const UNINITIALIZED_BITS: usize = 44;
    pub const NIL: Self = Self(0);
    pub const FALSE: Self = Self(Self::FALSE_BITS);
    pub const TRUE: Self = Self(84);
    pub const EOF: Self = Self(28);
    pub const UNSPECIFIED: Self = Self(Self::UNSPECIFIED_BITS);
    pub const UNINITIALIZED: Self = Self(Self::UNINITIALIZED_BITS);

    pub const fn bits(self) -> usize {
        self.0
    }

    pub const fn boolean(value: bool) -> Self {
        if value { Self::TRUE } else { Self::FALSE }
    }

    pub const fn character(value: char) -> Self {
        Self(((value as usize) << 6) | 12)
    }

    pub(crate) fn symbol(index: usize) -> Self {
        assert!(index <= usize::MAX >> 2, "symbol table exhausted");
        Self((index << 2) | 2)
    }

    pub fn as_symbol(self) -> Option<usize> {
        (self.0 & 3 == 2).then_some(self.0 >> 2)
    }

    pub fn fixnum(value: i64) -> Option<Self> {
        let word = isize::try_from(value).ok()?;
        (isize::MIN / 2..=isize::MAX / 2)
            .contains(&word)
            .then_some(Self((word as usize).wrapping_shl(1) | 1))
    }

    pub fn as_fixnum(self) -> Option<i64> {
        (self.0 & 1 != 0).then_some(((self.0 as isize) >> 1) as i64)
    }

    pub fn as_character(self) -> Option<char> {
        if self.0 & 63 != 12 {
            return None;
        }
        char::from_u32((self.0 >> 6) as u32)
    }

    pub fn is_boolean(self) -> bool {
        self == Self::FALSE || self == Self::TRUE
    }

    pub fn is_true(self) -> bool {
        self != Self::FALSE
    }

    pub fn address(self) -> Option<usize> {
        (self.0 != 0 && self.0 & 7 == 0).then_some(self.0)
    }

    pub(crate) fn integer(self, heap: &Heap) -> Result<i64, String> {
        self.as_integer(heap)
            .ok_or_else(|| "expected an exact integer".into())
    }

    pub(crate) fn as_integer(self, heap: &Heap) -> Option<i64> {
        self.as_fixnum()
            .or_else(|| heap.find::<Integer>(self).map(|n| n.0))
    }

    pub(crate) fn index(self, heap: &Heap) -> Result<usize, String> {
        usize::try_from(self.integer(heap)?).map_err(|_| "expected a nonnegative index".into())
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Number {
    Integer(i64),
    Float(f64),
}

impl Number {
    pub fn real(self) -> f64 {
        match self {
            Self::Integer(n) => n as f64,
            Self::Float(n) => n,
        }
    }
}

// ---- Fixed object layouts ----

/// Keep v3's numbers for the kinds it defines; append this VM's additional kinds.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u8)]
pub enum ObjectKind {
    Cell = 2,
    Float = 6,
    Text = 9,
    Pair = 10,
    Vector = 11,
    Closure = 13,
    Record = 14,
    RecordType = 15,
    Primitive = 16,
    Bytevector = 17,
    Integer = 18,
    Port = 19,
    Extension = 20,
    Continuation = 21,
}

mod sealed {
    pub trait Sealed {}
}

/// A closed set of fixed layouts. Foreign objects use `Extension` instead.
pub(crate) trait SnailSchemeObject: sealed::Sealed {
    const KIND: ObjectKind;
}

macro_rules! object {
    ($name:ident) => {
        impl sealed::Sealed for $name {}
        impl SnailSchemeObject for $name {
            const KIND: ObjectKind = ObjectKind::$name;
        }
    };
}

#[derive(Debug)]
#[repr(C)]
pub struct Pair(pub Value, pub Value);
object!(Pair);
#[derive(Debug)]
#[repr(C)]
pub struct Vector(pub Vec<Value>);
object!(Vector);
#[derive(Debug)]
#[repr(C)]
pub struct Cell(pub Value);
object!(Cell);
#[derive(Clone, Debug)]
#[repr(C)]
pub struct Closure {
    pub entry: u32,
    pub required: usize,
    pub has_rest: bool,
    pub locals: usize,
    pub captures: Vec<Value>,
}
object!(Closure);
/// A reusable copy of the active stack suffix. Frame metadata is immediate;
/// object words keep their identities, including shared mutable binding cells.
#[derive(Debug)]
#[repr(C)]
pub struct Continuation {
    pub stack: Vec<Value>,
    // Pending application headers are not linked through f; retain their count
    // for statistics instead of trying to reconstruct it from the saved stack.
    pub frames: u32,
}
object!(Continuation);
#[derive(Debug)]
#[repr(C)]
pub struct Record {
    pub descriptor: Value,
    pub fields: Vec<Value>,
}
object!(Record);
#[derive(Debug)]
#[repr(C)]
pub struct RecordType {
    pub name: String,
    pub fields: Vec<String>,
}
object!(RecordType);
#[derive(Debug)]
#[repr(C)]
pub struct Primitive(pub crate::primitives::Builtin);
object!(Primitive);
#[derive(Debug)]
#[repr(C)]
pub struct Bytevector(pub Vec<u8>);
object!(Bytevector);
#[derive(Debug)]
#[repr(C)]
pub struct Integer(pub i64);
object!(Integer);
#[derive(Debug)]
#[repr(C)]
pub struct Float(pub f64);
object!(Float);
object!(Port);

/// v3's count/pointer/ownership string layout, with UTF-8 construction checked.
#[derive(Debug)]
#[repr(C)]
pub struct Text {
    byte_count: usize,
    bytes: *mut u8,
    owned: bool,
}
object!(Text);

impl Text {
    pub fn new(text: String) -> Self {
        let bytes = text.into_bytes().into_boxed_slice();
        Self {
            byte_count: bytes.len(),
            bytes: Box::into_raw(bytes).cast(),
            owned: true,
        }
    }

    // Preserve v3's immortal-byte case even while runtime constructors use owned strings.
    #[allow(dead_code)]
    pub fn borrowed(text: &'static str) -> Self {
        Self {
            byte_count: text.len(),
            bytes: text.as_ptr().cast_mut(),
            owned: false,
        }
    }

    pub fn as_str(&self) -> &str {
        // Constructors accept only UTF-8 and no operation mutates these bytes.
        let bytes = unsafe { std::slice::from_raw_parts(self.bytes, self.byte_count) };
        unsafe { std::str::from_utf8_unchecked(bytes) }
    }
}

impl Drop for Text {
    fn drop(&mut self) {
        if self.owned {
            let bytes = std::ptr::slice_from_raw_parts_mut(self.bytes, self.byte_count);
            unsafe { drop(Box::from_raw(bytes)) };
        }
    }
}

// ---- Foreign extension objects ----

/// The visitor/context pair lets every host language report strong Scheme edges.
pub type GcVisit = unsafe extern "C" fn(context: *mut c_void, edge: Value);

#[repr(C)]
pub struct ExtensionVTable {
    pub gc_mark: unsafe extern "C" fn(payload: *const c_void, visit: GcVisit, context: *mut c_void),
    pub drop: unsafe extern "C" fn(payload: *mut c_void),
}

#[repr(C)]
pub struct Extension {
    payload: *mut c_void,
    vtable: &'static ExtensionVTable,
}
object!(Extension);

impl Extension {
    /// # Safety
    /// Transfer ownership of `payload` to this object. The callbacks must accept
    /// it until `drop` runs exactly once. `gc_mark` must visit every live, same-VM
    /// Scheme child; neither callback may allocate Scheme objects, collect,
    /// invoke Scheme, retain the visitor/context, or unwind through the C ABI.
    /// Visiting is synchronous and single-threaded. Destruction must not inspect
    /// Scheme children: sweep may already have destroyed those objects.
    pub unsafe fn from_raw(payload: *mut c_void, vtable: &'static ExtensionVTable) -> Self {
        Self { payload, vtable }
    }

    pub fn payload(&self) -> *mut c_void {
        self.payload
    }

    fn gc_mark(&self, pending: &mut Vec<Value>) {
        unsafe extern "C" fn visit(context: *mut c_void, edge: Value) {
            unsafe { &mut *context.cast::<Vec<Value>>() }.push(edge);
        }
        unsafe { (self.vtable.gc_mark)(self.payload, visit, std::ptr::from_mut(pending).cast()) };
    }
}

impl Drop for Extension {
    fn drop(&mut self) {
        unsafe { (self.vtable.drop)(self.payload) };
    }
}

// ---- Ownership and collection ----

#[derive(Clone, Copy, Debug, Default)]
pub struct GcStatistics {
    pub collections: u64,
    pub total_nanoseconds: u64,
    pub max_nanoseconds: u64,
    pub allocated: u64,
    pub reclaimed: u64,
    pub live: usize,
    pub peak: usize,
}

#[repr(C, align(8))]
struct Header {
    kind: ObjectKind,
    marked: bool,
}

/// `word` must be an immediate or a live allocation; no collection may intervene.
pub(crate) unsafe fn object_kind(word: u32) -> Option<ObjectKind> {
    let address = Value(word as usize).address()?;
    let pointer = std::ptr::with_exposed_provenance::<Header>(address);
    Some(unsafe { (*pointer).kind })
}

#[repr(C)]
struct Boxed<T> {
    header: Header,
    object: T,
}

pub(crate) struct Heap {
    objects: Vec<NonNull<Header>>,
    statistics: GcStatistics,
    since_collection: usize,
    collection_budget: usize,
}

impl Heap {
    pub(crate) fn new(_access: &HeapAccess) -> Self {
        Self {
            objects: Vec::new(),
            statistics: GcStatistics::default(),
            since_collection: 0,
            collection_budget: 0,
        }
    }

    pub(crate) fn allocate<T: SnailSchemeObject>(
        &mut self,
        object: T,
        _access: &HeapAccess,
    ) -> Value {
        let allocation = Box::new(Boxed {
            header: Header {
                kind: T::KIND,
                marked: false,
            },
            object,
        });
        let pointer = Box::into_raw(allocation);
        self.objects
            .push(unsafe { NonNull::new_unchecked(pointer.cast()) });
        self.record_allocation();
        Value(pointer.expose_provenance())
    }

    fn record_allocation(&mut self) {
        self.statistics.allocated += 1;
        self.statistics.live += 1;
        self.statistics.peak = self.statistics.peak.max(self.statistics.live);
        self.since_collection += 1;
    }

    pub(crate) fn integer(&mut self, value: i64, access: &HeapAccess) -> Value {
        Value::fixnum(value).unwrap_or_else(|| self.allocate(Integer(value), access))
    }

    pub(crate) fn number(&self, value: Value) -> Result<Number, String> {
        if let Some(integer) = value.as_integer(self) {
            return Ok(Number::Integer(integer));
        }
        self.find::<Float>(value)
            .map(|n| Number::Float(n.0))
            .ok_or_else(|| "expected a number".into())
    }

    /// `value` must be immediate or name a live allocation owned by this heap.
    pub(crate) fn find<T: SnailSchemeObject>(&self, value: Value) -> Option<&T> {
        let pointer = std::ptr::with_exposed_provenance::<Boxed<T>>(value.address()?);
        // Only the sealed implementation associates T with its unique kind.
        (unsafe { (*pointer).header.kind } == T::KIND).then(|| unsafe { &(*pointer).object })
    }

    pub(crate) fn get<T: SnailSchemeObject>(&self, value: Value) -> Result<&T, String> {
        self.find(value).ok_or_else(expected_type::<T>)
    }

    pub(crate) fn get_mut<T: SnailSchemeObject>(&mut self, value: Value) -> Result<&mut T, String> {
        let address = value.address().ok_or_else(expected_type::<T>)?;
        let pointer = std::ptr::with_exposed_provenance_mut::<Boxed<T>>(address);
        if unsafe { (*pointer).header.kind } != T::KIND {
            return Err(expected_type::<T>());
        }
        Ok(unsafe { &mut (*pointer).object })
    }

    /// Test allocation membership without dereferencing a possibly reclaimed word.
    /// Address reuse means this cannot establish a stale value's original identity.
    #[cfg(test)]
    pub(crate) fn contains(&self, value: Value) -> bool {
        self.objects.iter().any(|p| p.as_ptr().addr() == value.0)
    }

    pub(crate) fn should_collect(&self) -> bool {
        self.since_collection >= self.collection_budget.max(1024)
    }

    pub(crate) fn collect(&mut self, roots: impl IntoIterator<Item = Value>, _access: &HeapAccess) {
        let mut pending: Vec<Value> = roots.into_iter().collect();
        while let Some(value) = pending.pop() {
            if let Some(address) = value.address() {
                let header = std::ptr::with_exposed_provenance_mut::<Header>(address);
                unsafe { gc_mark(header, &mut pending) };
            }
        }
        self.sweep();
    }

    fn sweep(&mut self) {
        self.objects.retain_mut(|pointer| {
            let header = unsafe { pointer.as_mut() };
            if std::mem::take(&mut header.marked) {
                return true;
            }
            unsafe { destroy_object(*pointer) };
            false
        });
        self.finish_collection();
    }

    fn finish_collection(&mut self) {
        let live = self.objects.len();
        self.statistics.reclaimed += (self.statistics.live - live) as u64;
        self.statistics.live = live;
        self.since_collection = 0;
        self.collection_budget = live.max(1024);
    }

    pub(crate) fn record_collection_time(&mut self, nanoseconds: u64) {
        self.statistics.collections += 1;
        self.statistics.total_nanoseconds = self
            .statistics
            .total_nanoseconds
            .saturating_add(nanoseconds);
        self.statistics.max_nanoseconds = self.statistics.max_nanoseconds.max(nanoseconds);
    }

    pub(crate) fn statistics(&self) -> GcStatistics {
        self.statistics
    }

    #[cfg(test)]
    pub(crate) fn live_objects(&self) -> usize {
        self.statistics.live
    }
}

impl Drop for Heap {
    fn drop(&mut self) {
        for pointer in self.objects.drain(..) {
            unsafe { destroy_object(pointer) };
        }
    }
}

/// The only unchecked payload cast. Callers dispatch on the matching header kind.
unsafe fn payload<'a, T>(header: *const Header) -> &'a T {
    unsafe { &(*header.cast::<Boxed<T>>()).object }
}

unsafe fn gc_mark(header: *mut Header, pending: &mut Vec<Value>) {
    if unsafe { std::mem::replace(&mut (*header).marked, true) } {
        return;
    }
    // Keep this exhaustive: each fixed layout exposes its complete strong edges.
    unsafe {
        match (*header).kind {
            ObjectKind::Pair => {
                let pair = payload::<Pair>(header);
                pending.extend([pair.0, pair.1]);
            }
            ObjectKind::Vector => pending.extend(&payload::<Vector>(header).0),
            ObjectKind::Cell => pending.push(payload::<Cell>(header).0),
            ObjectKind::Closure => pending.extend(&payload::<Closure>(header).captures),
            ObjectKind::Continuation => pending.extend(&payload::<Continuation>(header).stack),
            ObjectKind::Record => {
                let record = payload::<Record>(header);
                pending.push(record.descriptor);
                pending.extend(&record.fields);
            }
            ObjectKind::Extension => payload::<Extension>(header).gc_mark(pending),
            ObjectKind::Float
            | ObjectKind::Text
            | ObjectKind::RecordType
            | ObjectKind::Primitive
            | ObjectKind::Bytevector
            | ObjectKind::Integer
            | ObjectKind::Port => {}
        }
    }
}

unsafe fn destroy_box<T>(pointer: NonNull<Header>) {
    unsafe { drop(Box::from_raw(pointer.as_ptr().cast::<Boxed<T>>())) };
}

unsafe fn destroy_object(pointer: NonNull<Header>) {
    unsafe {
        match pointer.as_ref().kind {
            ObjectKind::Pair => destroy_box::<Pair>(pointer),
            ObjectKind::Vector => destroy_box::<Vector>(pointer),
            ObjectKind::Cell => destroy_box::<Cell>(pointer),
            ObjectKind::Closure => destroy_box::<Closure>(pointer),
            ObjectKind::Continuation => destroy_box::<Continuation>(pointer),
            ObjectKind::Record => destroy_box::<Record>(pointer),
            ObjectKind::RecordType => destroy_box::<RecordType>(pointer),
            ObjectKind::Text => destroy_box::<Text>(pointer),
            ObjectKind::Primitive => destroy_box::<Primitive>(pointer),
            ObjectKind::Bytevector => destroy_box::<Bytevector>(pointer),
            ObjectKind::Integer => destroy_box::<Integer>(pointer),
            ObjectKind::Float => destroy_box::<Float>(pointer),
            ObjectKind::Port => destroy_box::<Port>(pointer),
            ObjectKind::Extension => destroy_box::<Extension>(pointer),
        }
    }
}

fn expected_type<T>() -> String {
    format!(
        "expected {}",
        std::any::type_name::<T>().rsplit("::").next().unwrap()
    )
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        cell::Cell as Counter,
        mem::{offset_of, size_of},
        rc::Rc,
    };

    #[test]
    fn fixed_layouts_preserve_v3_tags_kinds_and_fields() {
        assert_eq!(size_of::<Value>(), size_of::<usize>());
        assert_eq!(Value::NIL.bits(), 0);
        assert_eq!(Value::FALSE.bits(), 20);
        assert_eq!(Value::TRUE.bits(), 84);
        assert_eq!(Value::EOF.bits(), 28);
        assert_eq!(Value::UNSPECIFIED.bits(), 36);
        assert_eq!(Pair::KIND as u8, 10);
        assert_eq!(Vector::KIND as u8, 11);
        assert_eq!(Text::KIND as u8, 9);
        assert_eq!(Cell::KIND as u8, 2);
        assert_eq!(Float::KIND as u8, 6);
        assert_eq!(size_of::<Pair>(), 2 * size_of::<Value>());
        assert_eq!(offset_of!(Pair, 1), size_of::<Value>());
        assert_eq!(offset_of!(Boxed<Pair>, object), size_of::<Header>());
    }

    #[test]
    fn tagged_words_keep_exact_integers_outside_the_fixnum_range() {
        let mut heap = Heap::new(&HeapAccess::for_test());
        let minimum = (isize::MIN / 2) as i64;
        let maximum = (isize::MAX / 2) as i64;
        for number in [
            i64::MIN,
            minimum - 1,
            minimum,
            -1,
            0,
            maximum,
            maximum + 1,
            i64::MAX,
        ] {
            let value = heap.integer(number, &HeapAccess::for_test());
            assert_eq!(value.integer(&heap).unwrap(), number);
            assert_eq!(
                value.as_fixnum().is_some(),
                (minimum..=maximum).contains(&number)
            );
            assert!(!value.is_boolean());
            assert!(value.as_character().is_none());
            assert!(value.as_symbol().is_none());
        }
    }

    #[test]
    fn immediates_are_disjoint_from_objects_and_one_another() {
        let values = [
            Value::NIL,
            Value::FALSE,
            Value::TRUE,
            Value::EOF,
            Value::UNSPECIFIED,
            Value::UNINITIALIZED,
            Value::character('\0'),
            Value::character('λ'),
            Value::character('\u{10ffff}'),
            Value::symbol(0),
            Value::symbol(usize::MAX >> 2),
        ];
        for (index, value) in values.iter().enumerate() {
            assert!(!values[..index].contains(value));
            assert!(value.address().is_none());
            assert!(value.as_fixnum().is_none());
        }
        assert_eq!(
            Value::character('\u{10ffff}').as_character(),
            Some('\u{10ffff}')
        );
        assert_eq!(Value::symbol(17).as_symbol(), Some(17));
        assert!(!Value::FALSE.is_true());
        assert!(Value::NIL.is_true());
    }

    #[test]
    fn strings_own_or_borrow_the_v3_byte_array() {
        for text in [Text::new("aλ😀".into()), Text::borrowed("aλ😀")] {
            assert_eq!(text.byte_count, 7);
            assert_eq!(text.as_str(), "aλ😀");
        }
        assert_eq!(Text::new(String::new()).as_str(), "");
        assert_eq!(Text::borrowed("").as_str(), "");
    }

    struct Foreign {
        child: Value,
        dropped: Rc<Counter<usize>>,
    }

    unsafe extern "C" fn mark_foreign(
        payload: *const c_void,
        visit: GcVisit,
        context: *mut c_void,
    ) {
        let foreign = unsafe { &*payload.cast::<Foreign>() };
        unsafe { visit(context, foreign.child) };
    }

    unsafe extern "C" fn drop_foreign(payload: *mut c_void) {
        let foreign = unsafe { Box::from_raw(payload.cast::<Foreign>()) };
        foreign.dropped.set(foreign.dropped.get() + 1);
    }

    static FOREIGN_VTABLE: ExtensionVTable = ExtensionVTable {
        gc_mark: mark_foreign,
        drop: drop_foreign,
    };

    #[test]
    fn foreign_extension_vtable_traces_edges_and_drops_exactly_once() {
        let mut heap = Heap::new(&HeapAccess::for_test());
        let dropped = Rc::new(Counter::new(0));
        let child = heap.allocate(
            Text::new("retained by extension".into()),
            &HeapAccess::for_test(),
        );
        let foreign = Box::new(Foreign {
            child,
            dropped: dropped.clone(),
        });
        let extension =
            unsafe { Extension::from_raw(Box::into_raw(foreign).cast(), &FOREIGN_VTABLE) };
        let root = heap.allocate(extension, &HeapAccess::for_test());
        let address = root.address().unwrap();
        for _ in 0..2048 {
            heap.allocate(Pair(Value::NIL, Value::NIL), &HeapAccess::for_test());
        }
        heap.collect([root], &HeapAccess::for_test());
        assert_eq!(heap.live_objects(), 2);
        assert_eq!(root.address(), Some(address));
        assert_eq!(
            heap.get::<Text>(child).unwrap().as_str(),
            "retained by extension"
        );
        assert!(heap.get::<Pair>(root).is_err());
        heap.collect([], &HeapAccess::for_test());
        assert_eq!(dropped.get(), 1);
        assert!(!heap.contains(child));
        assert_eq!(heap.statistics().allocated, heap.statistics().reclaimed);
        drop(heap);
        assert_eq!(dropped.get(), 1);
    }

    #[test]
    fn collector_handles_cycles_without_moving_live_objects() {
        let mut heap = Heap::new(&HeapAccess::for_test());
        let pair = heap.allocate(Pair(Value::NIL, Value::NIL), &HeapAccess::for_test());
        let cell = heap.allocate(Cell(pair), &HeapAccess::for_test());
        heap.get_mut::<Pair>(pair).unwrap().1 = cell;
        heap.collect([pair], &HeapAccess::for_test());
        assert_eq!(heap.get::<Cell>(cell).unwrap().0, pair);
        assert_eq!(heap.live_objects(), 2);
        heap.collect([], &HeapAccess::for_test());
        assert_eq!(heap.live_objects(), 0);
    }

    #[test]
    fn continuation_snapshot_traces_words_and_reclaims_them_when_unreachable() {
        let access = HeapAccess::for_test();
        let mut heap = Heap::new(&access);
        let child = heap.allocate(Text::new("saved stack local".into()), &access);
        let saved = heap.allocate(
            Continuation {
                stack: vec![Value::NIL, child],
                frames: 0,
            },
            &access,
        );
        heap.collect([saved], &access);
        assert_eq!(
            heap.get::<Text>(child).unwrap().as_str(),
            "saved stack local"
        );
        assert_eq!(heap.live_objects(), 2);
        heap.collect([], &access);
        assert_eq!(heap.live_objects(), 0);
    }

    #[test]
    fn floats_and_boxed_integers_remain_roots_across_collection() {
        let mut heap = Heap::new(&HeapAccess::for_test());
        let integer = heap.integer(i64::MAX, &HeapAccess::for_test());
        let float = heap.allocate(Float(f64::INFINITY), &HeapAccess::for_test());
        let root = heap.allocate(Vector(vec![integer, float]), &HeapAccess::for_test());
        heap.collect([root], &HeapAccess::for_test());
        assert_eq!(heap.number(integer), Ok(Number::Integer(i64::MAX)));
        assert_eq!(heap.number(float), Ok(Number::Float(f64::INFINITY)));
        assert_eq!(heap.live_objects(), 3);
    }
}
