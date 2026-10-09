//! Explicit Scheme activations and continuations. Rust calls never nest according
//! to the Scheme call graph: every invocation returns a generated-code label.

use std::collections::{HashMap, HashSet};

use crate::{
    heap::{Closure, Heap, Object},
    host::{Host, Port},
    primitives::{self, PrimitiveResult},
    value::Value,
};

pub const STOP: u32 = u32::MAX;

#[derive(Default, Debug)]
struct Activation {
    closure: Option<Value>,
    locals: Vec<Value>,
    operand_base: usize,
}

#[derive(Debug)]
enum Frame {
    Return { activation: Activation, resume: u32 },
    Consume { consumer: Value },
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
        let input = heap.allocate(Object::Port(Port::Stdin));
        let output = heap.allocate(Object::Port(Port::Stdout));
        let error = heap.allocate(Object::Port(Port::Stderr));
        Self {
            heap,
            host: Host::new(input, output, error),
            argv,
            globals: vec![Value::Uninitialized; global_count as usize],
            constants: vec![Value::Uninitialized; constant_count as usize],
            operands: Vec::new(),
            results: vec![Value::Unspecified],
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
        let mut roots = Vec::new();
        roots.extend_from_slice(&self.globals);
        roots.extend_from_slice(&self.constants);
        roots.extend_from_slice(&self.operands);
        roots.extend_from_slice(&self.results);
        roots.extend_from_slice(&self.activation.locals);
        roots.extend(self.activation.closure);
        roots.extend([self.host.input, self.host.output, self.host.error]);
        for frame in &self.frames {
            match frame {
                Frame::Return { activation, .. } => {
                    roots.extend_from_slice(&activation.locals);
                    roots.extend(activation.closure);
                }
                Frame::Consume { consumer } => roots.push(*consumer),
            }
        }
        self.heap.collect(roots);
        // Interning is weak: live symbols retain identity without keeping all
        // symbols ever read by a long-running compiler alive forever.
        self.symbols
            .retain(|_, value| self.heap.get(*value).is_ok());
    }

    /// Allocation is transitively GC-free until the current handler returns.
    pub(crate) fn alloc(&mut self, object: Object) -> Value {
        self.heap.allocate(object)
    }

    pub(crate) fn intern(&mut self, name: &str) -> Value {
        if let Some(value) = self.symbols.get(name) {
            return *value;
        }
        let value = self.alloc(Object::Symbol(name.to_owned()));
        self.symbols.insert(name.to_owned(), value);
        value
    }

    pub(crate) fn list(&mut self, values: &[Value]) -> Value {
        values.iter().rev().fold(Value::Nil, |tail, value| {
            self.alloc(Object::Pair(*value, tail))
        })
    }

    pub(crate) fn list_values(&self, mut list: Value) -> Result<Vec<Value>, String> {
        let mut values = Vec::new();
        let mut seen = HashSet::new();
        while list != Value::Nil {
            if let Value::Heap(index) = list
                && !seen.insert(index)
            {
                return Err("expected a proper list, got a cycle".into());
            }
            match self.heap.get(list)? {
                Object::Pair(car, cdr) => {
                    values.push(*car);
                    list = *cdr;
                }
                _ => return Err("expected a proper list".into()),
            }
        }
        Ok(values)
    }

    pub(crate) fn string(&self, value: Value) -> Result<String, String> {
        match self.heap.get(value)? {
            Object::String(text) => Ok(text.clone()),
            _ => Err("expected a string".into()),
        }
    }

    pub(crate) fn single(&self) -> Result<Value, String> {
        match self.results.as_slice() {
            [value] => Ok(*value),
            values => Err(format!("expected one value, received {}", values.len())),
        }
    }

    fn cell(&self, index: u32, free: bool) -> Result<Value, String> {
        let cells = if free {
            let closure = self.activation.closure.ok_or("no active closure")?;
            match self.heap.get(closure)? {
                Object::Closure(closure) => &closure.captures,
                _ => return Err("invalid active closure".into()),
            }
        } else {
            &self.activation.locals
        };
        cells
            .get(index as usize)
            .copied()
            .ok_or_else(|| "invalid lexical slot".into())
    }

    pub(crate) fn refer(&mut self, index: u32, kind: u32) -> Result<(), String> {
        let value = match kind {
            0 | 1 => match self.heap.get(self.cell(index, kind == 1)?)? {
                Object::Cell(value) => *value,
                _ => return Err("invalid lexical cell".into()),
            },
            2 => *self
                .globals
                .get(index as usize)
                .ok_or("invalid global slot")?,
            _ => *self
                .constants
                .get(index as usize)
                .ok_or("invalid constant slot")?,
        };
        if value == Value::Uninitialized {
            return Err("read of an uninitialized binding".into());
        }
        self.results = vec![value];
        Ok(())
    }

    pub(crate) fn assign(&mut self, index: u32, kind: u32) -> Result<(), String> {
        let value = self.single()?;
        if kind == 2 {
            *self
                .globals
                .get_mut(index as usize)
                .ok_or("invalid global slot")? = value;
        } else {
            let cell = self.cell(index, kind == 1)?;
            match self.heap.get_mut(cell)? {
                Object::Cell(contents) => *contents = value,
                _ => return Err("invalid lexical cell".into()),
            }
        }
        self.results = vec![Value::Unspecified];
        Ok(())
    }

    pub(crate) fn capture(&mut self, index: u32, free: bool) -> Result<(), String> {
        self.operands.push(self.cell(index, free)?);
        Ok(())
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
        let closure = self.alloc(Object::Closure(Closure {
            entry,
            required: required as usize,
            has_rest,
            locals: locals as usize,
            captures,
        }));
        self.results = vec![closure];
        Ok(())
    }

    pub(crate) fn push(&mut self) -> Result<(), String> {
        self.operands.push(self.single()?);
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
            match self.heap.get(procedure)? {
                Object::Closure(closure) => {
                    let (entry, required, has_rest, locals) = (
                        closure.entry,
                        closure.required,
                        closure.has_rest,
                        closure.locals,
                    );
                    return self
                        .enter_closure(procedure, &arguments, entry, required, has_rest, locals);
                }
                Object::Primitive(name) => {
                    let name = name.clone();
                    match primitives::primitive(self, &name, &arguments)? {
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
                        PrimitiveResult::Exit(code) => {
                            self.exit_code = code;
                            self.halted = true;
                            return Ok(STOP);
                        }
                    }
                }
                _ => return Err("attempted to call a non-procedure".into()),
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
            locals.push(self.alloc(Object::Cell(*value)));
        }
        if has_rest {
            let rest = self.list(&arguments[required..]);
            locals.push(self.alloc(Object::Cell(rest)));
        }
        while locals.len() < local_count {
            locals.push(self.alloc(Object::Cell(Value::Uninitialized)));
        }
        self.activation = Activation {
            closure: Some(procedure),
            locals,
            operand_base: self.operands.len(),
        };
        self.results = vec![Value::Unspecified];
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
        let value = self.alloc(Object::Primitive(name));
        *self
            .globals
            .get_mut(index as usize)
            .ok_or("invalid global slot")? = value;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn machine(globals: u32) -> Vm {
        let mut vm = Vm::new(globals, 0, vec!["test".into()]);
        vm.set_gc_stress(true);
        vm
    }

    fn closure(vm: &mut Vm, entry: u32, required: usize, rest: bool, locals: usize) -> Value {
        vm.alloc(Object::Closure(Closure {
            entry,
            required,
            has_rest: rest,
            locals,
            captures: vec![],
        }))
    }

    fn call(vm: &mut Vm, procedure: Value, args: &[Value], tail: bool) -> u32 {
        vm.operands.extend_from_slice(args);
        vm.results = vec![procedure];
        vm.safepoint();
        vm.call(args.len() as u32, 900, tail).unwrap()
    }

    #[test]
    fn repeated_tail_calls_reuse_the_caller_frame() {
        let mut vm = machine(1);
        let function = closure(&mut vm, 10, 1, false, 1);
        vm.globals[0] = function;
        assert_eq!(call(&mut vm, function, &[Value::Integer(5000)], false), 10);
        for expected in (1..=5000).rev() {
            vm.safepoint();
            vm.refer(0, 0).unwrap();
            assert_eq!(vm.single().unwrap(), Value::Integer(expected));
            assert_eq!(
                call(&mut vm, function, &[Value::Integer(expected - 1)], true),
                10
            );
        }
        vm.results = vec![Value::Integer(0)];
        assert_eq!(vm.return_values().unwrap(), 900);
        assert_eq!(vm.max_frames(), 1);
        vm.collect();
        assert!(vm.heap.live_objects() <= 5);
    }

    #[test]
    fn closure_captures_share_mutable_binding_cells() {
        let mut vm = machine(1);
        let outer = closure(&mut vm, 10, 1, false, 1);
        call(&mut vm, outer, &[Value::Integer(1)], false);
        vm.capture(0, false).unwrap();
        vm.close(20, 0, false, 0, 1).unwrap();
        let inner = vm.single().unwrap();
        vm.globals[0] = inner;
        vm.results = vec![Value::Integer(37)];
        vm.assign(0, 0).unwrap();
        assert_eq!(call(&mut vm, inner, &[], false), 20);
        vm.safepoint();
        vm.refer(0, 1).unwrap();
        assert_eq!(vm.single().unwrap(), Value::Integer(37));
        vm.results = vec![Value::Integer(22)];
        vm.assign(0, 1).unwrap();
        assert_eq!(vm.return_values().unwrap(), 900);
        vm.refer(0, 0).unwrap();
        assert_eq!(vm.single().unwrap(), Value::Integer(22));
    }

    #[test]
    fn primitive_calls_preserve_pending_outer_arguments() {
        let mut vm = machine(0);
        let plus = vm.alloc(Object::Primitive("+".into()));
        vm.operands.push(Value::Integer(99));
        assert_eq!(
            call(
                &mut vm,
                plus,
                &[Value::Integer(2), Value::Integer(3)],
                false
            ),
            900
        );
        assert_eq!(vm.operands, vec![Value::Integer(99)]);
        assert_eq!(vm.results(), &[Value::Integer(5)]);
    }

    #[test]
    fn apply_builds_a_rest_list_without_host_calls() {
        let mut vm = machine(0);
        let function = closure(&mut vm, 10, 1, true, 2);
        let apply = vm.alloc(Object::Primitive("apply".into()));
        let rest = vm.list(&[Value::Integer(2), Value::Integer(3)]);
        assert_eq!(
            call(&mut vm, apply, &[function, Value::Integer(1), rest], false),
            10
        );
        vm.safepoint();
        vm.refer(1, 0).unwrap();
        assert_eq!(
            vm.list_values(vm.single().unwrap()).unwrap(),
            vec![Value::Integer(2), Value::Integer(3)]
        );
    }

    #[test]
    fn multiple_values_and_the_consumer_survive_collection() {
        let mut vm = machine(0);
        let producer = closure(&mut vm, 10, 0, false, 0);
        let consumer = closure(&mut vm, 20, 2, false, 2);
        let cwv = vm.alloc(Object::Primitive("call-with-values".into()));
        assert_eq!(call(&mut vm, cwv, &[producer, consumer], false), 10);
        let first = vm.alloc(Object::String("first".into()));
        let second = vm.alloc(Object::String("second".into()));
        vm.results = vec![first, second];
        vm.safepoint();
        assert_eq!(vm.return_values().unwrap(), 20);
        vm.safepoint();
        vm.refer(0, 0).unwrap();
        assert_eq!(vm.string(vm.single().unwrap()).unwrap(), "first");
        vm.refer(1, 0).unwrap();
        assert_eq!(vm.string(vm.single().unwrap()).unwrap(), "second");
        assert_eq!(vm.return_values().unwrap(), 900);
    }

    #[test]
    fn collection_traces_live_cycles_and_reclaims_dead_cycles() {
        let mut vm = machine(0);
        let live = vm.alloc(Object::Pair(Value::Integer(1), Value::Nil));
        *vm.heap.get_mut(live).unwrap() = Object::Pair(Value::Integer(1), live);
        let dead = vm.alloc(Object::Pair(Value::Integer(2), Value::Nil));
        *vm.heap.get_mut(dead).unwrap() = Object::Pair(Value::Integer(2), dead);
        vm.results = vec![live];
        vm.collect();
        assert_eq!(vm.heap.live_objects(), 4);
        assert!(matches!(vm.heap.get(live), Ok(Object::Pair(_, tail)) if *tail == live));
        assert!(vm.heap.get(dead).is_err());
    }

    #[test]
    fn normal_collection_budget_triggers_repeatedly() {
        let mut vm = machine(0);
        vm.set_gc_stress(false);
        for _ in 0..4096 {
            vm.alloc(Object::Pair(Value::Integer(1), Value::Nil));
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
            crate::snail_refer_global(&mut vm, 0);
        }
        assert_eq!(vm.error(), Some("read of an uninitialized binding"));
        unsafe {
            crate::snail_push(&mut vm);
        }
        assert!(vm.operands.is_empty());
        assert_eq!(unsafe { crate::snail_call(&mut vm, 0, 1, 0) }, STOP);
    }
}
