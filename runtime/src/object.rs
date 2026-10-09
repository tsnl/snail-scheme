//! Tagged Scheme values and the precise, nonmoving object heap.
//!
//! Like v3, an odd word is a signed fixnum and an aligned address names a boxed
//! object. The word follows the target pointer width. Integers outside the fixnum
//! range remain exact by using a boxed i64; floating-point numbers are boxed too.
//! Allocation never collects. The VM owns the safepoints and supplies all roots.
//! A tagged address is looked up, never dereferenced. The ownership table returns
//! a Rust borrow of a live allocation. Values not rooted across collection are
//! invalid; address reuse can change their identity, but cannot cause a stale
//! pointer dereference. A header keeps trait-object metadata out of the value.

use crate::host::Port;
use std::{any::Any, collections::HashMap};

// ---- Tagged words ----

#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
#[repr(transparent)]
pub struct Value(usize);

impl Value {
    pub const FALSE_BITS: usize = 14;
    pub const UNSPECIFIED_BITS: usize = 38;
    pub const UNINITIALIZED_BITS: usize = 46;
    pub const fn bits(self) -> usize {
        self.0
    }

    pub const NIL: Self = Self(6);
    pub const FALSE: Self = Self(Self::FALSE_BITS);
    pub const TRUE: Self = Self(22);
    pub const EOF: Self = Self(30);
    pub const UNSPECIFIED: Self = Self(Self::UNSPECIFIED_BITS);
    pub const UNINITIALIZED: Self = Self(Self::UNINITIALIZED_BITS);

    pub const fn boolean(value: bool) -> Self {
        if value { Self::TRUE } else { Self::FALSE }
    }

    pub const fn character(value: char) -> Self {
        Self(((value as usize) << 3) | 2)
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
        if self.0 & 7 != 2 {
            return None;
        }
        char::from_u32((self.0 >> 3) as u32)
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

    pub fn integer(self, heap: &Heap) -> Result<i64, String> {
        self.as_integer(heap)
            .ok_or_else(|| "expected an exact integer".into())
    }

    pub fn as_integer(self, heap: &Heap) -> Option<i64> {
        self.as_fixnum()
            .or_else(|| heap.find::<Integer>(self).map(|n| n.0))
    }

    pub fn index(self, heap: &Heap) -> Result<usize, String> {
        usize::try_from(self.integer(heap)?).map_err(|_| "expected a nonnegative index".into())
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Number {
    Integer(i64),
    Float(f64),
}

impl Number {
    pub fn integer(self) -> Result<i64, String> {
        match self {
            Self::Integer(n) => Ok(n),
            Self::Float(_) => Err("expected an exact integer".into()),
        }
    }

    pub fn real(self) -> f64 {
        match self {
            Self::Integer(n) => n as f64,
            Self::Float(n) => n,
        }
    }
}

// ---- Boxed objects ----

/// Report every strong Scheme edge, without allocating or invoking Scheme.
/// Each concrete object has its own implementation and its own Rust layout.
pub trait SnailSchemeObject: Any {
    fn mark(&self, visit: &mut dyn FnMut(Value));
}

macro_rules! object {
    ($name:ident, $self:ident, $visit:ident, $mark:block) => {
        impl SnailSchemeObject for $name {
            fn mark(&$self, $visit: &mut dyn FnMut(Value)) $mark
        }
    };
    ($name:ident) => { object!($name, self, _visit, {}); };
}

#[derive(Debug)]
pub struct Pair(pub Value, pub Value);
object!(Pair, self, visit, {
    visit(self.0);
    visit(self.1);
});
#[derive(Debug)]
pub struct Vector(pub Vec<Value>);
object!(Vector, self, visit, {
    self.0.iter().copied().for_each(visit);
});
#[derive(Debug)]
pub struct Cell(pub Value);
object!(Cell, self, visit, {
    visit(self.0);
});
#[derive(Clone, Debug)]
pub struct Closure {
    pub entry: u32,
    pub required: usize,
    pub has_rest: bool,
    pub locals: usize,
    pub captures: Vec<Value>,
}
object!(Closure, self, visit, {
    self.captures.iter().copied().for_each(visit);
});
#[derive(Debug)]
pub struct Record {
    pub descriptor: Value,
    pub fields: Vec<Value>,
}
object!(Record, self, visit, {
    visit(self.descriptor);
    self.fields.iter().copied().for_each(visit);
});
#[derive(Debug)]
pub struct RecordType {
    pub name: String,
    pub fields: Vec<String>,
}
object!(RecordType);
#[derive(Debug)]
pub struct Text(pub String);
object!(Text);
#[derive(Debug)]
pub struct Symbol(pub String);
object!(Symbol);
#[derive(Debug)]
pub struct Primitive(pub String);
object!(Primitive);
#[derive(Debug)]
pub struct Bytevector(pub Vec<u8>);
object!(Bytevector);
#[derive(Debug)]
pub struct Integer(pub i64);
object!(Integer);
#[derive(Debug)]
pub struct Float(pub f64);
object!(Float);
object!(Port);

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

#[repr(align(8))]
struct Allocation {
    object: Box<dyn SnailSchemeObject>,
    marked: bool,
}

#[derive(Default)]
pub struct Heap {
    objects: HashMap<usize, Box<Allocation>>,
    statistics: GcStatistics,
    since_collection: usize,
    collection_budget: usize,
}

impl Heap {
    pub fn allocate(&mut self, object: impl SnailSchemeObject) -> Value {
        let allocation = Box::new(Allocation {
            object: Box::new(object),
            marked: false,
        });
        let address = (&*allocation as *const Allocation).addr();
        self.objects.insert(address, allocation);
        self.record_allocation();
        Value(address)
    }

    fn record_allocation(&mut self) {
        self.statistics.allocated += 1;
        self.statistics.live += 1;
        self.statistics.peak = self.statistics.peak.max(self.statistics.live);
        self.since_collection += 1;
    }

    pub fn integer(&mut self, value: i64) -> Value {
        Value::fixnum(value).unwrap_or_else(|| self.allocate(Integer(value)))
    }

    pub fn number(&self, value: Value) -> Result<Number, String> {
        if let Some(integer) = value.as_integer(self) {
            return Ok(Number::Integer(integer));
        }
        self.find::<Float>(value)
            .map(|n| Number::Float(n.0))
            .ok_or_else(|| "expected a number".into())
    }

    pub fn find<T: SnailSchemeObject>(&self, value: Value) -> Option<&T> {
        let object = self.objects.get(&value.0)?.object.as_ref();
        (object as &dyn Any).downcast_ref()
    }

    pub fn get<T: SnailSchemeObject>(&self, value: Value) -> Result<&T, String> {
        self.find(value).ok_or_else(expected_type::<T>)
    }

    pub fn get_mut<T: SnailSchemeObject>(&mut self, value: Value) -> Result<&mut T, String> {
        let allocation = self
            .objects
            .get_mut(&value.0)
            .ok_or_else(expected_type::<T>)?;
        (allocation.object.as_mut() as &mut dyn Any)
            .downcast_mut()
            .ok_or_else(expected_type::<T>)
    }

    pub fn contains(&self, value: Value) -> bool {
        self.objects.contains_key(&value.0)
    }

    pub fn should_collect(&self) -> bool {
        self.since_collection >= self.collection_budget.max(1024)
    }

    pub fn collect(&mut self, roots: impl IntoIterator<Item = Value>) {
        let mut pending: Vec<Value> = roots.into_iter().collect();
        while let Some(value) = pending.pop() {
            let Some(allocation) = self.objects.get_mut(&value.0) else {
                continue;
            };
            if allocation.marked {
                continue;
            }
            allocation.marked = true;
            allocation.object.mark(&mut |edge| pending.push(edge));
        }
        self.sweep();
    }

    fn sweep(&mut self) {
        self.objects.retain(|_, allocation| {
            let live = allocation.marked;
            allocation.marked = false;
            live
        });
        let live = self.objects.len();
        self.statistics.reclaimed += (self.statistics.live - live) as u64;
        self.statistics.live = live;
        self.since_collection = 0;
        self.collection_budget = live.max(1024);
    }

    pub fn record_collection_time(&mut self, nanoseconds: u64) {
        self.statistics.collections += 1;
        self.statistics.total_nanoseconds = self
            .statistics
            .total_nanoseconds
            .saturating_add(nanoseconds);
        self.statistics.max_nanoseconds = self.statistics.max_nanoseconds.max(nanoseconds);
    }

    pub fn statistics(&self) -> GcStatistics {
        self.statistics
    }
    pub fn live_objects(&self) -> usize {
        self.statistics.live
    }
}

fn expected_type<T>() -> String {
    format!(
        "expected {}",
        std::any::type_name::<T>().rsplit("::").next().unwrap()
    )
}

// ---- Tests ----

// Representation and collector invariants.
#[cfg(test)]
mod tests {
    use super::*;
    use std::{cell::Cell as Counter, rc::Rc};

    #[test]
    fn tagged_words_follow_pointer_width_without_losing_integer_precision() {
        assert_eq!(std::mem::size_of::<Value>(), std::mem::size_of::<usize>());
        let mut heap = Heap::default();
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
            let value = heap.integer(number);
            assert_eq!(value.integer(&heap).unwrap(), number);
            assert_eq!(
                value.as_fixnum().is_some(),
                (minimum..=maximum).contains(&number)
            );
            assert!(!value.is_boolean());
            assert!(value.as_character().is_none());
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
        assert!(!Value::FALSE.is_true());
        assert!(Value::NIL.is_true());
    }

    #[derive(Debug)]
    struct Extension {
        child: Value,
        dropped: Rc<Counter<usize>>,
    }
    object!(Extension, self, visit, {
        visit(self.child);
    });
    impl Drop for Extension {
        fn drop(&mut self) {
            self.dropped.set(self.dropped.get() + 1);
        }
    }

    #[test]
    fn dynamic_extensions_trace_edges_and_drop_when_unreachable() {
        let mut heap = Heap::default();
        let dropped = Rc::new(Counter::new(0));
        let child = heap.allocate(Text("retained by custom object".into()));
        let root = heap.allocate(Extension {
            child,
            dropped: dropped.clone(),
        });
        let address = root.address().unwrap();
        for _ in 0..2048 {
            heap.allocate(Pair(Value::NIL, Value::NIL));
        }
        heap.collect([root]);
        assert_eq!(heap.live_objects(), 2);
        assert_eq!(root.address(), Some(address));
        assert_eq!(heap.get::<Extension>(root).unwrap().child, child);
        assert!(heap.get::<Pair>(root).is_err());
        heap.collect([]);
        assert_eq!(dropped.get(), 1);
        assert!(heap.get::<Text>(child).is_err());
        assert_eq!(heap.statistics().allocated, heap.statistics().reclaimed);
    }

    #[test]
    fn floats_and_boxed_integers_remain_roots_across_collection() {
        let mut heap = Heap::default();
        let integer = heap.integer(i64::MAX);
        let float = heap.allocate(Float(f64::INFINITY));
        let root = heap.allocate(Vector(vec![integer, float]));
        heap.collect([root]);
        assert_eq!(heap.number(integer), Ok(Number::Integer(i64::MAX)));
        assert_eq!(heap.number(float), Ok(Number::Float(f64::INFINITY)));
        assert_eq!(heap.live_objects(), 3);
    }
}
