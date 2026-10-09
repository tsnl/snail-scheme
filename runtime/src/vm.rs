//! Explicit Scheme activations and continuations. Rust calls never nest according
//! to the Scheme call graph: every invocation returns a generated-code label.

use std::collections::{HashMap, HashSet};

use crate::{
    host::{Host, Port},
    object::*,
    primitives::{self, PrimitiveResult},
};

pub const STOP: u32 = u32::MAX;

#[derive(Debug)]
enum Local {
    Direct(Value),
    Captured(Value),
}

impl Local {
    fn root(&self) -> Value {
        match self {
            Self::Direct(value) | Self::Captured(value) => *value,
        }
    }

    fn slot(&mut self, heap: &mut Heap) -> Result<*mut Value, String> {
        match self {
            Self::Direct(value) => Ok(value),
            Self::Captured(cell) => Ok(&mut heap.get_mut::<Cell>(*cell)?.0),
        }
    }

    fn capture(&mut self, heap: &mut Heap) -> *mut Value {
        // Allocation cannot collect or resize the activation's local storage.
        // Publish the cell here before the next generated-code safepoint.
        if let Self::Direct(value) = self {
            *self = Self::Captured(heap.allocate(Cell(*value)));
        }
        match self {
            Self::Captured(cell) => cell,
            Self::Direct(_) => unreachable!(),
        }
    }
}

#[derive(Default, Debug)]
struct Activation {
    closure: Option<Value>,
    locals: Vec<Local>,
    operand_base: usize,
}

#[derive(Debug)]
enum Frame {
    Return { activation: Activation, resume: u32 },
    Consume { consumer: Value },
}

impl Activation {
    fn roots(&self, roots: &mut Vec<Value>) {
        roots.extend(self.locals.iter().map(Local::root));
        roots.extend(self.closure);
    }
}

impl Frame {
    fn roots(&self, roots: &mut Vec<Value>) {
        match self {
            Self::Return { activation, .. } => activation.roots(roots),
            Self::Consume { consumer } => roots.push(*consumer),
        }
    }
}

enum Dispatch {
    Call(Value, Vec<Value>),
    Return,
}

pub struct Vm {
    pub(crate) heap: Heap,
    pub(crate) host: Host,
    pub(crate) argv: Vec<String>,
    globals: Vec<Value>,
    constants: Vec<Value>,
    operands: Vec<Value>,
    results: Vec<Value>,
    activation: Activation,
    frames: Vec<Frame>,
    symbols: HashMap<String, Value>,
    error: Option<String>,
    halted: bool,
    exit_code: i32,
    stress_gc: bool,
    max_frames: usize,
}

impl Vm {
    pub fn new(global_count: u32, constant_count: u32, argv: Vec<String>) -> Self {
        let mut heap = Heap::default();
        let input = heap.allocate(Port::Stdin);
        let output = heap.allocate(Port::Stdout);
        let error = heap.allocate(Port::Stderr);
        Self {
            heap,
            host: Host::new(input, output, error),
            argv,
            globals: vec![Value::UNINITIALIZED; global_count as usize],
            constants: vec![Value::UNINITIALIZED; constant_count as usize],
            operands: Vec::new(),
            results: vec![Value::UNSPECIFIED],
            activation: Activation::default(),
            frames: Vec::new(),
            symbols: HashMap::new(),
            error: None,
            halted: false,
            exit_code: 0,
            stress_gc: std::env::var_os("SNAIL_GC_STRESS").is_some(),
            max_frames: 0,
        }
    }

    pub fn error(&self) -> Option<&str> {
        self.error.as_deref()
    }
    pub fn exit_code(&self) -> i32 {
        if self.error.is_some() {
            1
        } else {
            self.exit_code
        }
    }
    pub fn is_halted(&self) -> bool {
        self.halted
    }
    pub fn results(&self) -> &[Value] {
        &self.results
    }
    pub fn max_frames(&self) -> usize {
        self.max_frames
    }
    pub fn set_gc_stress(&mut self, enabled: bool) {
        self.stress_gc = enabled;
    }

    pub(crate) fn fail(&mut self, message: String) {
        if self.error.is_none() {
            self.error = Some(message);
        }
        self.halted = true;
    }

    /// The only automatic collection site. Call before removing handler inputs.
    pub(crate) fn safepoint(&mut self) {
        if self.stress_gc || self.heap.should_collect() {
            self.collect();
        }
    }

    pub fn collect(&mut self) {
        let started = std::time::Instant::now();
        self.heap.collect(self.roots());
        // Weak interned names disappear before any allocation can reuse addresses.
        self.symbols.retain(|_, value| self.heap.contains(*value));
        let nanoseconds = started.elapsed().as_nanos().min(u64::MAX as u128) as u64;
        self.heap.record_collection_time(nanoseconds);
    }

    fn roots(&self) -> Vec<Value> {
        let mut roots = Vec::new();
        for values in [
            &self.globals,
            &self.constants,
            &self.operands,
            &self.results,
        ] {
            roots.extend_from_slice(values);
        }
        self.activation.roots(&mut roots);
        roots.extend([self.host.input, self.host.output, self.host.error]);
        for frame in &self.frames {
            frame.roots(&mut roots);
        }
        roots
    }

    pub fn gc_statistics(&self) -> GcStatistics {
        self.heap.statistics()
    }
    pub(crate) fn integer(&mut self, value: i64) -> Value {
        self.heap.integer(value)
    }
    pub(crate) fn float(&mut self, value: f64) -> Value {
        self.alloc(Float(value))
    }

    /// Allocation never collects; safepoints are explicit VM operations.
    pub(crate) fn alloc(&mut self, object: impl SnailSchemeObject) -> Value {
        self.heap.allocate(object)
    }

    pub(crate) fn intern(&mut self, name: &str) -> Value {
        if let Some(value) = self.symbols.get(name) {
            return *value;
        }
        let value = self.alloc(Symbol(name.to_owned()));
        self.symbols.insert(name.to_owned(), value);
        value
    }

    pub(crate) fn list(&mut self, values: &[Value]) -> Value {
        values
            .iter()
            .rev()
            .fold(Value::NIL, |tail, value| self.alloc(Pair(*value, tail)))
    }

    pub(crate) fn list_values(&self, mut list: Value) -> Result<Vec<Value>, String> {
        let mut values = Vec::new();
        let mut seen = HashSet::new();
        while list != Value::NIL {
            if !seen.insert(list) {
                return Err("expected a proper list, got a cycle".into());
            }
            let Pair(car, cdr) = self.heap.get::<Pair>(list)?;
            values.push(*car);
            list = *cdr;
        }
        Ok(values)
    }

    pub(crate) fn string(&self, value: Value) -> Result<&str, String> {
        Ok(&self.heap.get::<Text>(value)?.0)
    }

    pub(crate) fn single(&self) -> Result<Value, String> {
        match self.results.as_slice() {
            [value] => Ok(*value),
            values => Err(format!("expected one value, received {}", values.len())),
        }
    }

    fn free_cell(&self, index: u32) -> Result<Value, String> {
        let closure = self.activation.closure.ok_or("no active closure")?;
        self.heap
            .get::<Closure>(closure)?
            .captures
            .get(index as usize)
            .copied()
            .ok_or_else(|| "invalid lexical slot".into())
    }

    /// Borrow only until the next VM operation. Generated code must load before
    /// growing a vector, and publish any live word before the next safepoint.
    pub(crate) fn slot(&mut self, index: u32, kind: u32) -> Result<*mut Value, String> {
        match kind {
            0 => self
                .activation
                .locals
                .get_mut(index as usize)
                .ok_or("invalid lexical slot")?
                .slot(&mut self.heap),
            1 => {
                let cell = self.free_cell(index)?;
                Ok(&mut self.heap.get_mut::<Cell>(cell)?.0)
            }
            2 => self
                .globals
                .get_mut(index as usize)
                .map(|v| v as *mut Value)
                .ok_or("invalid global slot".into()),
            3 => self
                .constants
                .get_mut(index as usize)
                .map(|v| v as *mut Value)
                .ok_or("invalid constant slot".into()),
            _ => Err("invalid slot kind".into()),
        }
    }

    pub(crate) fn capture_slot(&mut self, index: u32, free: bool) -> Result<*mut Value, String> {
        if !free {
            return Ok(self
                .activation
                .locals
                .get_mut(index as usize)
                .ok_or("invalid lexical slot")?
                .capture(&mut self.heap));
        }
        let closure = self.activation.closure.ok_or("no active closure")?;
        self.heap
            .get_mut::<Closure>(closure)?
            .captures
            .get_mut(index as usize)
            .map(|v| v as *mut Value)
            .ok_or("invalid lexical slot".into())
    }

    pub(crate) fn single_slot(&mut self) -> Result<*mut Value, String> {
        self.single()?;
        Ok(self.results.as_mut_ptr())
    }

    pub(crate) fn result_slot(&mut self) -> *mut Value {
        self.set_result(Value::UNSPECIFIED);
        self.results.as_mut_ptr()
    }

    fn set_result(&mut self, value: Value) {
        self.results.clear();
        self.results.push(value);
    }

    pub(crate) fn push_slot(&mut self) -> *mut Value {
        self.operands.push(Value::UNSPECIFIED);
        self.operands.last_mut().unwrap()
    }

    pub(crate) fn close(
        &mut self,
        entry: u32,
        required: u32,
        has_rest: bool,
        locals: u32,
        captures: u32,
    ) -> Result<(), String> {
        let start = self
            .operands
            .len()
            .checked_sub(captures as usize)
            .ok_or("not enough closure captures")?;
        let captures = self.operands.split_off(start);
        let closure = self.alloc(Closure {
            entry,
            required: required as usize,
            has_rest,
            locals: locals as usize,
            captures,
        });
        self.set_result(closure);
        Ok(())
    }

    pub(crate) fn call(&mut self, argc: u32, resume: u32, tail: bool) -> Result<u32, String> {
        let procedure = self.single()?;
        let start = self
            .operands
            .len()
            .checked_sub(argc as usize)
            .ok_or("not enough call operands")?;
        let arguments = self.operands.split_off(start);
        if tail {
            self.operands.truncate(self.activation.operand_base);
        } else {
            let activation = std::mem::take(&mut self.activation);
            self.frames.push(Frame::Return { activation, resume });
            self.max_frames = self.max_frames.max(self.frames.len());
        }
        self.activation = Activation {
            operand_base: self.operands.len(),
            ..Activation::default()
        };
        self.dispatch(Dispatch::Call(procedure, arguments))
    }

    /// Dispatches a call until Scheme code needs to run. Neither apply nor
    /// call-with-values enters generated code through the Rust call stack.
    fn dispatch(&mut self, mut action: Dispatch) -> Result<u32, String> {
        loop {
            let (procedure, arguments) = match action {
                Dispatch::Call(procedure, arguments) => (procedure, arguments),
                Dispatch::Return => {
                    self.operands.truncate(self.activation.operand_base);
                    match self.frames.pop() {
                        Some(Frame::Return { activation, resume }) => {
                            self.activation = activation;
                            return Ok(resume);
                        }
                        Some(Frame::Consume { consumer }) => {
                            (consumer, std::mem::take(&mut self.results))
                        }
                        None => {
                            self.halted = true;
                            return Ok(STOP);
                        }
                    }
                }
            };
            if let Some(closure) = self.heap.find::<Closure>(procedure) {
                let (entry, required, has_rest, locals) = (
                    closure.entry,
                    closure.required,
                    closure.has_rest,
                    closure.locals,
                );
                return self
                    .enter_closure(procedure, &arguments, entry, required, has_rest, locals);
            } else if let Some(Primitive(name)) = self.heap.find::<Primitive>(procedure) {
                let name = name.clone();
                match primitives::primitive(self, &name, &arguments)? {
                    PrimitiveResult::Value(value) => {
                        self.set_result(value);
                        action = Dispatch::Return;
                    }
                    PrimitiveResult::Values(values) => {
                        self.results = values;
                        action = Dispatch::Return;
                    }
                    PrimitiveResult::Invoke(next, args) => {
                        action = Dispatch::Call(next, args);
                    }
                    PrimitiveResult::CallWithValues(producer, consumer) => {
                        self.frames.push(Frame::Consume { consumer });
                        self.max_frames = self.max_frames.max(self.frames.len());
                        action = Dispatch::Call(producer, Vec::new());
                    }
                    PrimitiveResult::Collect => {
                        // All inputs are consumed. Publish the sole result before
                        // this explicit safepoint; no consumed input is used afterward.
                        self.set_result(Value::UNSPECIFIED);
                        self.collect();
                        action = Dispatch::Return;
                    }
                    PrimitiveResult::Exit(code) => {
                        self.exit_code = code;
                        self.halted = true;
                        return Ok(STOP);
                    }
                }
            } else {
                return Err("attempted to call a non-procedure".into());
            }
        }
    }

    fn enter_closure(
        &mut self,
        procedure: Value,
        arguments: &[Value],
        entry: u32,
        required: usize,
        has_rest: bool,
        local_count: usize,
    ) -> Result<u32, String> {
        if arguments.len() < required || (!has_rest && arguments.len() != required) {
            return Err(format!(
                "procedure expected {}{} arguments, received {}",
                required,
                if has_rest { " or more" } else { "" },
                arguments.len()
            ));
        }
        if local_count < required + usize::from(has_rest) {
            return Err("invalid closure local count".into());
        }
        let mut locals = Vec::with_capacity(local_count);
        for value in &arguments[..required] {
            locals.push(Local::Direct(*value));
        }
        if has_rest {
            let rest = self.list(&arguments[required..]);
            locals.push(Local::Direct(rest));
        }
        while locals.len() < local_count {
            locals.push(Local::Direct(Value::UNINITIALIZED));
        }
        self.activation = Activation {
            closure: Some(procedure),
            locals,
            operand_base: self.operands.len(),
        };
        self.set_result(Value::UNSPECIFIED);
        Ok(entry)
    }

    pub(crate) fn return_values(&mut self) -> Result<u32, String> {
        self.dispatch(Dispatch::Return)
    }

    pub(crate) fn halt(&mut self) {
        self.halted = true;
    }

    pub(crate) fn set_constant(&mut self, index: u32, value: Value) -> Result<(), String> {
        *self
            .constants
            .get_mut(index as usize)
            .ok_or("invalid constant slot")? = value;
        Ok(())
    }

    pub(crate) fn constant(&self, index: u32) -> Result<Value, String> {
        self.constants
            .get(index as usize)
            .copied()
            .ok_or_else(|| "invalid constant slot".into())
    }

    pub(crate) fn global_primitive(&mut self, index: u32, name: String) -> Result<(), String> {
        let value = self.alloc(Primitive(name));
        *self
            .globals
            .get_mut(index as usize)
            .ok_or("invalid global slot")? = value;
        Ok(())
    }
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    fn integer(value: i64) -> Value {
        Value::fixnum(value).unwrap()
    }

    fn slot_value(vm: &mut Vm, index: u32, kind: u32) -> Value {
        unsafe { *vm.slot(index, kind).unwrap() }
    }

    fn machine(globals: u32) -> Vm {
        let mut vm = Vm::new(globals, 0, vec!["test".into()]);
        vm.set_gc_stress(true);
        vm
    }

    fn closure(vm: &mut Vm, entry: u32, required: usize, rest: bool, locals: usize) -> Value {
        vm.alloc(Closure {
            entry,
            required,
            has_rest: rest,
            locals,
            captures: vec![],
        })
    }

    fn call(vm: &mut Vm, procedure: Value, args: &[Value], tail: bool) -> u32 {
        vm.operands.extend_from_slice(args);
        vm.results = vec![procedure];
        vm.safepoint();
        vm.call(args.len() as u32, 900, tail).unwrap()
    }

    fn capture(vm: &mut Vm, index: u32, free: bool) -> Value {
        unsafe { *vm.capture_slot(index, free).unwrap() }
    }

    #[test]
    fn ordinary_locals_do_not_allocate_managed_objects() {
        let mut vm = machine(0);
        let function = closure(&mut vm, 10, 1, false, 2);
        let allocated = vm.gc_statistics().allocated;
        assert_eq!(call(&mut vm, function, &[integer(1)], false), 10);
        assert_eq!(vm.gc_statistics().allocated, allocated);
        assert_eq!(slot_value(&mut vm, 1, 0), Value::UNINITIALIZED);
        unsafe {
            *vm.slot(0, 0).unwrap() = integer(2);
        }
        assert_eq!(slot_value(&mut vm, 0, 0), integer(2));
    }

    #[test]
    fn saved_caller_locals_keep_heap_values_alive() {
        let mut vm = machine(0);
        let outer = closure(&mut vm, 10, 1, false, 1);
        let retained = vm.alloc(Text("saved caller local".into()));
        call(&mut vm, outer, &[retained], false);
        let inner = closure(&mut vm, 20, 0, false, 0);
        call(&mut vm, inner, &[], false);
        vm.collect();
        assert_eq!(vm.return_values().unwrap(), 900);
        let retained = slot_value(&mut vm, 0, 0);
        assert_eq!(vm.string(retained).unwrap(), "saved caller local");
    }

    #[test]
    fn explicit_collection_keeps_caller_operands_and_records_statistics() {
        let mut vm = machine(0);
        vm.set_gc_stress(false);
        let retained = vm.alloc(Text("pending caller argument".into()));
        vm.operands.push(retained);
        vm.alloc(Text("garbage".into()));
        let collect = vm.alloc(Primitive("collect-garbage".into()));
        assert_eq!(call(&mut vm, collect, &[], false), 900);
        assert_eq!(
            vm.string(vm.operands[0]).unwrap(),
            "pending caller argument"
        );
        let stats = vm.gc_statistics();
        assert_eq!(stats.collections, 1);
        assert_eq!(stats.allocated - stats.reclaimed, stats.live as u64);
        assert!(stats.reclaimed >= 2);
        assert!(stats.max_nanoseconds <= stats.total_nanoseconds);
        assert!(stats.live <= stats.peak);
    }

    #[test]
    fn repeated_tail_calls_reuse_the_caller_frame() {
        let mut vm = machine(1);
        let function = closure(&mut vm, 10, 1, false, 1);
        vm.globals[0] = function;
        assert_eq!(call(&mut vm, function, &[integer(5000)], false), 10);
        for expected in (1..=5000).rev() {
            vm.safepoint();
            assert_eq!(slot_value(&mut vm, 0, 0), integer(expected));
            assert_eq!(call(&mut vm, function, &[integer(expected - 1)], true), 10);
        }
        vm.results = vec![integer(0)];
        assert_eq!(vm.return_values().unwrap(), 900);
        assert_eq!(vm.max_frames(), 1);
        vm.collect();
        assert!(vm.heap.live_objects() <= 5);
    }

    #[test]
    fn closure_captures_share_mutable_binding_cells() {
        let mut vm = machine(1);
        let outer = closure(&mut vm, 10, 1, false, 1);
        call(&mut vm, outer, &[integer(1)], false);
        unsafe {
            *vm.slot(0, 0).unwrap() = integer(7);
        }
        let allocated = vm.gc_statistics().allocated;
        let cell = capture(&mut vm, 0, false);
        assert_eq!(capture(&mut vm, 0, false), cell);
        assert_eq!(vm.gc_statistics().allocated, allocated + 1);
        assert_eq!(vm.heap.get::<Cell>(cell).unwrap().0, integer(7));
        vm.operands.push(cell);
        vm.close(20, 0, false, 0, 1).unwrap();
        let inner = vm.single().unwrap();
        vm.globals[0] = inner;
        unsafe {
            *vm.slot(0, 0).unwrap() = integer(37);
        }
        assert_eq!(call(&mut vm, inner, &[], false), 20);
        vm.safepoint();
        assert_eq!(slot_value(&mut vm, 0, 1), integer(37));
        unsafe {
            *vm.slot(0, 1).unwrap() = integer(22);
        }
        assert_eq!(vm.return_values().unwrap(), 900);
        assert_eq!(slot_value(&mut vm, 0, 0), integer(22));
    }

    #[test]
    fn tail_replacement_leaves_escaped_captures_and_forwarded_cells_alive() {
        let mut vm = machine(1);
        let outer = closure(&mut vm, 10, 1, false, 1);
        let retained = vm.alloc(Text("escaped binding".into()));
        call(&mut vm, outer, &[retained], false);
        let cell = capture(&mut vm, 0, false);
        vm.operands.push(cell);
        vm.close(20, 0, false, 0, 1).unwrap();
        let inner = vm.single().unwrap();
        vm.globals[0] = inner;
        call(&mut vm, outer, &[integer(99)], true);
        assert_eq!(slot_value(&mut vm, 0, 0), integer(99));
        call(&mut vm, inner, &[], true);
        vm.collect();
        assert_eq!(capture(&mut vm, 0, true), cell);
        let retained = slot_value(&mut vm, 0, 1);
        assert_eq!(vm.string(retained).unwrap(), "escaped binding");
        let forwarded_cell = capture(&mut vm, 0, true);
        vm.operands.push(forwarded_cell);
        vm.close(30, 0, false, 0, 1).unwrap();
        let forwarded = vm.single().unwrap();
        vm.globals[0] = Value::UNINITIALIZED;
        vm.return_values().unwrap();
        call(&mut vm, forwarded, &[], false);
        vm.collect();
        assert_eq!(capture(&mut vm, 0, true), cell);
        let retained = slot_value(&mut vm, 0, 1);
        assert_eq!(vm.string(retained).unwrap(), "escaped binding");
    }

    #[test]
    fn primitive_calls_preserve_pending_outer_arguments() {
        let mut vm = machine(0);
        let plus = vm.alloc(Primitive("+".into()));
        vm.operands.push(integer(99));
        assert_eq!(call(&mut vm, plus, &[integer(2), integer(3)], false), 900);
        assert_eq!(vm.operands, vec![integer(99)]);
        assert_eq!(vm.results(), &[integer(5)]);
    }

    #[test]
    fn apply_builds_a_rest_list_without_host_calls() {
        let mut vm = machine(0);
        let function = closure(&mut vm, 10, 1, true, 2);
        let apply = vm.alloc(Primitive("apply".into()));
        let rest = vm.list(&[integer(2), integer(3)]);
        let allocated = vm.gc_statistics().allocated;
        assert_eq!(
            call(&mut vm, apply, &[function, integer(1), rest], false),
            10
        );
        assert_eq!(vm.gc_statistics().allocated, allocated + 2);
        vm.safepoint();
        let rest = slot_value(&mut vm, 1, 0);
        assert_eq!(vm.list_values(rest).unwrap(), vec![integer(2), integer(3)]);
    }

    #[test]
    fn multiple_values_and_the_consumer_survive_collection() {
        let mut vm = machine(0);
        let producer = closure(&mut vm, 10, 0, false, 0);
        let consumer = closure(&mut vm, 20, 2, false, 2);
        let cwv = vm.alloc(Primitive("call-with-values".into()));
        assert_eq!(call(&mut vm, cwv, &[producer, consumer], false), 10);
        let first = vm.alloc(Text("first".into()));
        let second = vm.alloc(Text("second".into()));
        vm.results = vec![first, second];
        vm.safepoint();
        assert_eq!(vm.return_values().unwrap(), 20);
        vm.safepoint();
        let first = slot_value(&mut vm, 0, 0);
        let second = slot_value(&mut vm, 1, 0);
        assert_eq!(vm.string(first).unwrap(), "first");
        assert_eq!(vm.string(second).unwrap(), "second");
        assert_eq!(vm.return_values().unwrap(), 900);
    }

    #[test]
    fn collection_traces_live_cycles_and_reclaims_dead_cycles() {
        let mut vm = machine(0);
        let live = vm.alloc(Pair(integer(1), Value::NIL));
        *vm.heap.get_mut::<Pair>(live).unwrap() = Pair(integer(1), live);
        let dead = vm.alloc(Pair(integer(2), Value::NIL));
        *vm.heap.get_mut::<Pair>(dead).unwrap() = Pair(integer(2), dead);
        vm.results = vec![live];
        vm.collect();
        assert_eq!(vm.heap.live_objects(), 4);
        assert!(matches!(vm.heap.get::<Pair>(live), Ok(Pair(_, tail)) if *tail == live));
        assert!(!vm.heap.contains(dead));
    }

    #[test]
    fn normal_collection_budget_triggers_repeatedly() {
        let mut vm = machine(0);
        vm.set_gc_stress(false);
        for _ in 0..4096 {
            vm.alloc(Pair(integer(1), Value::NIL));
            vm.safepoint();
        }
        // Only the three ports survive each collection. The remaining objects
        // were allocated since the most recent, independently triggered cycle.
        assert!(vm.heap.live_objects() < 1027);
    }

    #[test]
    fn uninitialized_bindings_fail_and_later_handlers_are_noops() {
        let mut vm = machine(1);
        unsafe {
            crate::snail_rt_uninitialized(&mut vm);
        }
        assert_eq!(vm.error(), Some("read of an uninitialized binding"));
        unsafe {
            assert!(crate::snail_rt_push(&mut vm).is_null());
        }
        assert!(vm.operands.is_empty());
        assert_eq!(unsafe { crate::snail_rt_call(&mut vm, 0, 1, 0) }, STOP);
    }
}
