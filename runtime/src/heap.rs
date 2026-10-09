//! A precise, nonmoving mark-and-sweep heap.
//!
//! Handles index stable slots; the objects themselves stay in their original
//! boxes. Allocation never collects. The VM collects only at handler boundaries,
//! when all live Scheme values have been published in its explicit roots.

use crate::{host::Port, value::Value};

#[derive(Clone, Debug)]
pub struct Closure {
    pub entry: u32,
    pub required: usize,
    pub has_rest: bool,
    pub locals: usize,
    pub captures: Vec<Value>,
}

#[derive(Debug)]
pub enum Object {
    Pair(Value, Value),
    Vector(Vec<Value>),
    Bytevector(Vec<u8>),
    String(String),
    Symbol(String),
    Cell(Value),
    Closure(Closure),
    Primitive(String),
    RecordType {
        name: String,
        fields: Vec<String>,
    },
    Record {
        descriptor: Value,
        fields: Vec<Value>,
    },
    Port(Port),
}

/// Reports strong edges. The collector owns mark bits and the iterative worklist.
/// Implementations must report every managed reference and must not allocate.
pub trait SnailSchemeObject {
    fn mark(&self, visit: &mut dyn FnMut(Value));
}

impl SnailSchemeObject for Object {
    fn mark(&self, visit: &mut dyn FnMut(Value)) {
        match self {
            Self::Pair(a, b) => {
                visit(*a);
                visit(*b);
            }
            Self::Vector(values) => values.iter().copied().for_each(visit),
            Self::Cell(value) => visit(*value),
            Self::Closure(closure) => closure.captures.iter().copied().for_each(visit),
            Self::Record { descriptor, fields } => {
                visit(*descriptor);
                fields.iter().copied().for_each(visit);
            }
            _ => {}
        }
    }
}

#[derive(Default)]
pub struct Heap {
    slots: Vec<Option<Box<Object>>>,
    free: Vec<usize>,
    live: usize,
    since_collection: usize,
    collection_budget: usize,
}

impl Heap {
    pub fn allocate(&mut self, object: Object) -> Value {
        let slot = match self.free.pop() {
            Some(index) => {
                self.slots[index] = Some(Box::new(object));
                index
            }
            None => {
                self.slots.push(Some(Box::new(object)));
                self.slots.len() - 1
            }
        };
        self.live += 1;
        self.since_collection += 1;
        Value::Heap(slot)
    }

    pub fn get(&self, value: Value) -> Result<&Object, String> {
        match value {
            Value::Heap(index) => self
                .slots
                .get(index)
                .and_then(Option::as_deref)
                .ok_or_else(|| "invalid heap reference".into()),
            _ => Err("expected a heap object".into()),
        }
    }

    pub fn get_mut(&mut self, value: Value) -> Result<&mut Object, String> {
        match value {
            Value::Heap(index) => self
                .slots
                .get_mut(index)
                .and_then(Option::as_deref_mut)
                .ok_or_else(|| "invalid heap reference".into()),
            _ => Err("expected a heap object".into()),
        }
    }

    pub fn should_collect(&self) -> bool {
        self.since_collection >= self.collection_budget.max(1024)
    }

    pub fn collect(&mut self, roots: impl IntoIterator<Item = Value>) {
        let mut marked = vec![false; self.slots.len()];
        let mut pending: Vec<Value> = roots.into_iter().collect();
        while let Some(value) = pending.pop() {
            if let Value::Heap(index) = value {
                if index >= marked.len() || marked[index] {
                    continue;
                }
                if let Some(object) = self.slots[index].as_ref() {
                    marked[index] = true;
                    object.mark(&mut |edge| pending.push(edge));
                }
            }
        }
        for (index, slot) in self.slots.iter_mut().enumerate() {
            if slot.is_some() && !marked[index] {
                *slot = None;
                self.free.push(index);
                self.live -= 1;
            }
        }
        self.since_collection = 0;
        // Fix the next budget now. Comparing against a live count that grows
        // on every allocation would continually move the collection threshold.
        self.collection_budget = self.live.max(1024);
    }

    #[cfg(test)]
    pub fn live_objects(&self) -> usize {
        self.live
    }
}
