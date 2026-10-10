//! One reusable, downward-growing Scheme stack, owned by the Rust VM thread.
//! LLVM implements Dybvig's frame/argument/shift/apply/return transitions;
//! Rust provides heap and host operations at explicit allocation boundaries.

use crate::{
    host::{Host, Port},
    object::*,
    primitives::{self, PrimitiveResult},
};
use std::collections::{HashMap, HashSet};
pub const STOP: u32 = u32::MAX;
pub const CONSUME: u32 = u32::MAX - 1;

// Application actions are shared with machine.sld, independently of code labels.
const ENTER_SCHEME: u32 = 0;
const RETURN_VALUES: u32 = 1;
const APPLY_ARGUMENTS: u32 = 2;
const PRODUCE_VALUES: u32 = 3;
const CAPTURE_CONTINUATION: u32 = 4;
const RESTORE_CONTINUATION: u32 = 5;
const STOPPED: u32 = 255;

// ---- Rust runtime services and allocation capability ----

/// Sibling modules can read/mutate heap fields but cannot mint this authority.
/// It gates low-level allocation/collection without forwarding every accessor.
/// Only this module creates it; Allocation keeps its copy private from callables.
pub(crate) struct HeapAccess(());

impl HeapAccess {
    #[cfg(test)]
    pub(crate) fn for_test() -> Self {
        Self(())
    }
}

/// A Rust callable can access object fields and host services, but not VM roots
/// or collection. Only an owned Allocation permits managed construction.
pub(crate) struct Runtime {
    pub(crate) heap: Heap,
    pub(crate) host: Host,
    pub(crate) argv: Vec<String>,
    symbols: HashMap<std::rc::Rc<str>, Value>,
    symbol_names: Vec<std::rc::Rc<str>>,
}

impl Runtime {
    fn new(argv: Vec<String>) -> Self {
        let access = HeapAccess(());
        let mut heap = Heap::new(&access);
        let input = heap.allocate(Port::Stdin, &access);
        let output = heap.allocate(Port::Stdout, &access);
        let error = heap.allocate(Port::Stderr, &access);
        Self {
            heap,
            host: Host::new(input, output, error),
            argv,
            symbols: HashMap::new(),
            symbol_names: Vec::new(),
        }
    }

    // Symbol IDs and backing names live as long as the VM, like v3's intern table.
    // Interning allocates Rust storage, never a managed object or a safepoint.
    pub(crate) fn intern(&mut self, name: &str) -> Value {
        if let Some(value) = self.symbols.get(name) {
            return *value;
        }
        let value = Value::symbol(self.symbol_names.len());
        let name: std::rc::Rc<str> = name.into();
        self.symbol_names.push(name.clone());
        self.symbols.insert(name, value);
        value
    }

    pub(crate) fn symbol_name(&self, value: Value) -> Result<&str, String> {
        value
            .as_symbol()
            .and_then(|index| self.symbol_names.get(index))
            .map(|name| name.as_ref())
            .ok_or_else(|| "expected a symbol".into())
    }

    pub(crate) fn string(&self, value: Value) -> Result<&str, String> {
        Ok(self.heap.get::<Text>(value)?.as_str())
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

    pub(crate) fn gc_statistics(&self) -> GcStatistics {
        self.heap.statistics()
    }

    #[cfg(test)]
    pub(crate) fn for_test(argv: Vec<String>) -> Self {
        Self::new(argv)
    }

    /// Unit tests construct an isolated allocation burst with collection disabled.
    #[cfg(test)]
    pub(crate) fn allocation(&mut self) -> Allocation<'_> {
        Allocation {
            runtime: self,
            access: HeapAccess(()),
        }
    }
}

/// One GC-free Rust operation. The VM creates this only after its boundary poll;
/// construction and destruction of managed values never poll inside the call.
/// No Drop implementation: ending a burst must not collect unrooted results.
pub(crate) struct Allocation<'a> {
    runtime: &'a mut Runtime,
    access: HeapAccess,
}

impl std::ops::Deref for Allocation<'_> {
    type Target = Runtime;
    fn deref(&self) -> &Runtime {
        self.runtime
    }
}
impl std::ops::DerefMut for Allocation<'_> {
    fn deref_mut(&mut self) -> &mut Runtime {
        self.runtime
    }
}
impl Allocation<'_> {
    pub(crate) fn alloc(&mut self, object: impl SnailSchemeObject) -> Value {
        self.runtime.heap.allocate(object, &self.access)
    }
    pub(crate) fn integer(&mut self, value: i64) -> Value {
        self.runtime.heap.integer(value, &self.access)
    }
    pub(crate) fn float(&mut self, value: f64) -> Value {
        self.alloc(Float(value))
    }
    pub(crate) fn list(&mut self, values: &[Value]) -> Value {
        values
            .iter()
            .rev()
            .fold(Value::NIL, |tail, value| self.alloc(Pair(*value, tail)))
    }
}

// ---- Downward-growing Scheme stack ----

/// The only layout shared with generated LLVM. Every field is one 32-bit word.
/// Depths are measured from stack_end, so growth does not change saved frames.
/// Generated code owns ordinary register, frame, argument, and return transitions.
#[repr(C)]
pub struct State {
    pub a: Value,
    pub c: Value,
    pub s: u32,
    pub f: u32,
    pub result_count: u32,
    pub stack_end: *mut Value,
    pub capacity: u32,
    pub globals: *mut Value,
    pub constants: *mut Value,
    pub argc: u32,
    pub entry: u32,
    pub locals: u32,
    pub frames: u32,
    pub max_frames: u32,
    pub stopped: u32,
}

pub struct Vm {
    state: State,
    runtime: Runtime,
    globals: Vec<Value>,
    constants: Vec<Value>,
    stack: Vec<Value>,
    multiple: Vec<Value>,
    error: Option<String>,
    exit_code: i32,
    stress_gc: bool,
}

impl Vm {
    pub fn new(global_count: u32, constant_count: u32, argv: Vec<String>) -> Self {
        let mut globals = vec![Value::UNINITIALIZED; global_count as usize];
        let mut constants = vec![Value::UNINITIALIZED; constant_count as usize];
        let mut stack = vec![Value::UNINITIALIZED; 256];
        let end = stack.len();
        stack[end - 1] = Value::NIL;
        stack[end - 2] = Value::fixnum(0).unwrap();
        stack[end - 3] = Value::fixnum(-1).unwrap();
        Self {
            state: State {
                a: Value::UNSPECIFIED,
                c: Value::NIL,
                s: 3,
                f: 0,
                result_count: 1,
                stack_end: stack.as_mut_ptr().wrapping_add(end),
                capacity: end as u32,
                globals: globals.as_mut_ptr(),
                constants: constants.as_mut_ptr(),
                argc: 0,
                entry: 0,
                locals: 0,
                frames: 1,
                max_frames: 1,
                stopped: 0,
            },
            runtime: Runtime::new(argv),
            globals,
            constants,
            stack,
            multiple: Vec::new(),
            error: None,
            exit_code: 0,
            stress_gc: std::env::var_os("SNAIL_GC_STRESS").is_some(),
        }
    }

    pub(crate) fn state(&mut self) -> *mut State {
        &mut self.state
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
        self.state.stopped != 0
    }
    pub fn max_frames(&self) -> usize {
        self.state.max_frames as usize
    }
    pub fn set_gc_stress(&mut self, enabled: bool) {
        self.stress_gc = enabled;
    }
    pub fn gc_statistics(&self) -> GcStatistics {
        self.runtime.gc_statistics()
    }
    pub(crate) fn halt(&mut self) {
        self.state.stopped = 1;
    }

    pub(crate) fn fail(&mut self, message: String) {
        if self.error.is_none() {
            self.error = Some(message);
        }
        self.halt();
    }

    pub fn results(&self) -> &[Value] {
        match self.state.result_count {
            0 => &[],
            1 => std::slice::from_ref(&self.state.a),
            count => &self.multiple[..count as usize],
        }
    }

    pub(crate) fn single(&self) -> Result<Value, String> {
        if self.state.result_count == 1 {
            Ok(self.state.a)
        } else {
            Err(format!(
                "expected one value, received {}",
                self.state.result_count
            ))
        }
    }

    fn set_result(&mut self, value: Value) {
        self.state.a = value;
        self.state.result_count = 1;
    }

    fn word(&self, depth: u32) -> Value {
        self.stack[self.stack.len() - depth as usize]
    }
    fn put(&mut self, depth: u32, value: Value) {
        let index = self.stack.len() - depth as usize;
        self.stack[index] = value;
    }

    /// Storage growth never collects. Active words move together to the new high
    /// end; saved depths and all references to heap objects remain unchanged.
    pub(crate) fn reserve(&mut self, depth: u32) -> Result<(), String> {
        if depth <= self.state.capacity {
            return Ok(());
        }
        if depth > (isize::MAX as u32 / 4) {
            return Err("Scheme stack exhausted".into());
        }
        let old = self.stack.len();
        let size = (old * 2).max(depth as usize).min(isize::MAX as usize / 4);
        self.stack.resize(size, Value::UNINITIALIZED);
        self.stack.copy_within(
            old - self.state.s as usize..old,
            size - self.state.s as usize,
        );
        self.state.stack_end = self.stack.as_mut_ptr().wrapping_add(size);
        self.state.capacity = size as u32;
        Ok(())
    }

    // ---- Root publication and allocation boundaries ----

    fn poll(&mut self) {
        if self.stress_gc || self.runtime.heap.should_collect() {
            self.collect();
        }
    }

    /// Extra roots are published startup operands, never a traced Rust stack.
    pub(crate) fn allocation(&mut self, extra: impl IntoIterator<Item = Value>) -> Allocation<'_> {
        if self.stress_gc || self.runtime.heap.should_collect() {
            self.collect_with(extra);
        }
        Allocation {
            runtime: &mut self.runtime,
            access: HeapAccess(()),
        }
    }

    pub fn collect(&mut self) {
        self.collect_with([]);
    }

    fn collect_with(&mut self, extra: impl IntoIterator<Item = Value>) {
        let started = snail_trace::span("runtime.gc");
        let mut roots = self.roots();
        roots.extend(extra);
        self.runtime.heap.collect(roots, &HeapAccess(()));
        let nanoseconds = started.elapsed().as_nanos().min(u64::MAX as u128) as u64;
        self.runtime.heap.record_collection_time(nanoseconds);
    }

    fn roots(&self) -> Vec<Value> {
        let mut roots = vec![
            self.state.a,
            self.state.c,
            self.runtime.host.input,
            self.runtime.host.output,
            self.runtime.host.error,
        ];
        roots.extend_from_slice(&self.globals);
        roots.extend_from_slice(&self.constants);
        roots.extend_from_slice(&self.stack[self.stack.len() - self.state.s as usize..]);
        roots.extend_from_slice(self.results());
        roots
    }

    // ---- Heap-backed bindings and closures ----

    pub(crate) fn box_local(&mut self, index: u32) -> Result<(), String> {
        let depth = self.state.f + index + 1;
        if depth > self.state.s {
            return Err("invalid lexical slot".into());
        }
        let value = self.word(depth);
        let cell = self.allocation([]).alloc(Cell(value));
        self.put(depth, cell);
        Ok(())
    }

    pub(crate) fn cell_slot(&mut self, cell: Value) -> Result<*mut Value, String> {
        Ok(&mut self.runtime.heap.get_mut::<Cell>(cell)?.0)
    }

    pub(crate) fn free_slot(&mut self, index: u32) -> Result<*mut Value, String> {
        self.runtime
            .heap
            .get_mut::<Closure>(self.state.c)?
            .captures
            .get_mut(index as usize)
            .map(|v| v as *mut Value)
            .ok_or_else(|| "invalid lexical slot".into())
    }

    pub(crate) fn close(
        &mut self,
        entry: u32,
        required: u32,
        has_rest: bool,
        locals: u32,
        count: u32,
    ) -> Result<(), String> {
        let start = self
            .state
            .s
            .checked_sub(count)
            .ok_or("not enough closure captures")?;
        self.poll();
        let captures = (start + 1..=self.state.s)
            .map(|depth| self.word(depth))
            .collect();
        let value = self.runtime.heap.allocate(
            Closure {
                entry,
                required: required as usize,
                has_rest,
                locals: locals as usize,
                captures,
            },
            &HeapAccess(()),
        );
        self.state.s = start;
        self.set_result(value);
        Ok(())
    }

    // ---- Application preparation; ordinary control stays in LLVM ----

    /// Actions: Scheme=0, return=1, apply=2, values producer=3, capture=4,
    /// restore=5. No service invokes Scheme recursively through the Rust stack.
    pub(crate) fn prepare_apply(&mut self, argc: u32) -> Result<u32, String> {
        self.state.argc = argc;
        let procedure = self.state.c;
        if self.runtime.heap.find::<Closure>(procedure).is_some() {
            self.prepare_closure(argc)?;
            Ok(ENTER_SCHEME)
        } else if self.runtime.heap.find::<Continuation>(procedure).is_some() {
            Ok(RESTORE_CONTINUATION)
        } else if let Some(Primitive(builtin)) = self.runtime.heap.find::<Primitive>(procedure) {
            self.prepare_primitive(*builtin, argc)
        } else {
            Err("attempted to call a non-procedure".into())
        }
    }

    fn prepare_closure(&mut self, argc: u32) -> Result<(), String> {
        let closure = self.runtime.heap.get::<Closure>(self.state.c)?;
        let (entry, required, rest, locals) = (
            closure.entry,
            closure.required,
            closure.has_rest,
            closure.locals,
        );
        if (argc as usize) < required || (!rest && argc as usize != required) {
            return Err(format!(
                "procedure expected {}{} arguments, received {}",
                required,
                if rest { " or more" } else { "" },
                argc
            ));
        }
        if locals < required + usize::from(rest) {
            return Err("invalid closure local count".into());
        }
        self.state.entry = entry;
        self.state.locals = locals as u32;
        if rest {
            self.prepare_rest(required as u32, argc)?;
        }
        Ok(())
    }

    fn prepare_rest(&mut self, required: u32, argc: u32) -> Result<(), String> {
        self.poll();
        let mut rest = Value::NIL;
        for index in (required..argc).rev() {
            rest = self.runtime.heap.allocate(
                Pair(self.word(self.state.f + index + 1), rest),
                &HeapAccess(()),
            );
        }
        let depth = self.state.f + required + 1;
        self.reserve(depth)?;
        self.put(depth, rest);
        self.state.s = depth;
        Ok(())
    }

    fn prepare_primitive(
        &mut self,
        builtin: primitives::Builtin,
        argc: u32,
    ) -> Result<u32, String> {
        use primitives::Builtin::*;
        match builtin {
            Values => {
                self.arguments_to_results(argc);
                Ok(RETURN_VALUES)
            }
            CallWithValues => {
                self.control_arity(builtin, argc, 2)?;
                Ok(PRODUCE_VALUES)
            }
            CallWithCurrentContinuation => {
                self.control_arity(builtin, argc, 1)?;
                Ok(CAPTURE_CONTINUATION)
            }
            _ => self.invoke_primitive(builtin, argc),
        }
    }

    fn control_arity(
        &self,
        builtin: primitives::Builtin,
        argc: u32,
        expected: u32,
    ) -> Result<(), String> {
        if argc == expected {
            Ok(())
        } else {
            Err(format!(
                "{}: wrong number of arguments (got {argc})",
                builtin.name()
            ))
        }
    }

    fn invoke_primitive(&mut self, builtin: primitives::Builtin, argc: u32) -> Result<u32, String> {
        let result = self.call_primitive(builtin, argc, self.state.f)?;
        self.accept_primitive(result)
    }

    /// Poll before borrowing the argument slice. A Rust callable sees Runtime,
    /// never Vm: it cannot collect, grow this stack, or restore a continuation.
    /// Arguments presents source order without moving the downward stack words.
    fn call_primitive(
        &mut self,
        builtin: primitives::Builtin,
        argc: u32,
        base: u32,
    ) -> Result<PrimitiveResult, String> {
        let allocates = builtin.may_allocate();
        if allocates {
            self.poll();
        }
        let end = self.stack.len() - base as usize;
        let arguments = primitives::Arguments(&self.stack[end - argc as usize..end]);
        if allocates {
            primitives::invoke_allocating(
                Allocation {
                    runtime: &mut self.runtime,
                    access: HeapAccess(()),
                },
                builtin,
                arguments,
            )
        } else {
            primitives::invoke(&mut self.runtime, builtin, arguments)
        }
    }

    /// Numeric fast paths retain f/c and root operands through s. Polling
    /// also traces a/c, so the current environment needs no extra call frame.
    pub(crate) fn numeric(&mut self, global: u32) -> Result<(), String> {
        let builtin = self.numeric_builtin(global)?;
        let base = self.state.s - 2;
        let PrimitiveResult::Value(value) = self.call_primitive(builtin, 2, base)? else {
            unreachable!("numeric primitive cannot change control flow");
        };
        self.set_result(value);
        self.state.s = base;
        Ok(())
    }

    fn numeric_builtin(&self, global: u32) -> Result<primitives::Builtin, String> {
        use primitives::Builtin::*;
        let Primitive(builtin) = *self
            .runtime
            .heap
            .get::<Primitive>(self.globals[global as usize])?;
        match builtin {
            Add | Subtract | NumericEqual | Less | LessEqual | Greater | GreaterEqual => {
                Ok(builtin)
            }
            _ => Err("invalid numeric instruction builtin".into()),
        }
    }

    fn accept_primitive(&mut self, result: PrimitiveResult) -> Result<u32, String> {
        match result {
            PrimitiveResult::Value(value) => self.set_result(value),
            PrimitiveResult::Invoke(procedure, args) => {
                self.replace_arguments(procedure, &args)?;
                return Ok(APPLY_ARGUMENTS);
            }
            PrimitiveResult::Collect => {
                self.state.s = self.state.f;
                self.set_result(Value::UNSPECIFIED);
                self.collect();
            }
            PrimitiveResult::Exit(code) => {
                self.exit_code = code;
                self.halt();
                return Ok(STOPPED);
            }
        }
        Ok(RETURN_VALUES)
    }

    fn replace_arguments(&mut self, procedure: Value, args: &[Value]) -> Result<(), String> {
        self.reserve(self.state.f + args.len() as u32)?;
        for (index, value) in args.iter().enumerate() {
            self.put(self.state.f + index as u32 + 1, *value);
        }
        self.state.s = self.state.f + args.len() as u32;
        self.state.argc = args.len() as u32;
        self.set_result(procedure);
        Ok(())
    }

    fn arguments_to_results(&mut self, argc: u32) {
        if argc == 1 {
            self.set_result(self.word(self.state.f + 1));
            return;
        }
        self.multiple.clear();
        for index in 0..argc {
            self.multiple.push(self.word(self.state.f + index + 1));
        }
        self.state.a = Value::UNSPECIFIED;
        self.state.result_count = argc;
    }

    pub(crate) fn receive(&mut self) -> Result<(), String> {
        let consumer = self.word(self.state.f + 2);
        let count = self.state.result_count;
        self.reserve(self.state.f + count)?;
        for index in 0..count {
            let value = if count == 1 {
                self.state.a
            } else {
                self.multiple[index as usize]
            };
            self.put(self.state.f + index + 1, value);
        }
        self.state.s = self.state.f + count;
        self.state.argc = count;
        self.set_result(consumer);
        Ok(())
    }

    // ---- Immutable multi-shot continuation snapshots ----

    /// Capture the stack through the current return header. The call/cc argument
    /// is consumed; invoking this image resumes the common LLVM return operation.
    pub(crate) fn capture(&mut self) -> Result<(), String> {
        self.poll();
        let stack = self.stack[self.stack.len() - self.state.f as usize..].to_vec();
        let value = self.runtime.heap.allocate(
            Continuation {
                stack,
                frames: self.state.frames,
            },
            &HeapAccess(()),
        );
        self.set_result(value);
        Ok(())
    }

    /// Preserve incoming values first. Growth and copying cannot collect, and
    /// the snapshot stays immutable for later invocations. Tagged frame words
    /// restore c/f/pc through LLVM's ordinary return transition.
    pub(crate) fn restore(&mut self, argc: u32) -> Result<(), String> {
        let continuation = self.state.c;
        self.arguments_to_results(argc);
        let depth = self
            .runtime
            .heap
            .get::<Continuation>(continuation)?
            .stack
            .len() as u32;
        self.reserve(depth)?;
        let snapshot = self.runtime.heap.get::<Continuation>(continuation)?;
        let start = self.stack.len() - depth as usize;
        self.stack[start..].copy_from_slice(&snapshot.stack);
        self.state.f = depth;
        self.state.s = depth;
        self.state.frames = snapshot.frames;
        self.state.max_frames = self.state.max_frames.max(snapshot.frames);
        Ok(())
    }

    // ---- Startup constants and globals ----

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
        let builtin = primitives::Builtin::from_name(&name)?;
        let value = self.allocation([]).alloc(Primitive(builtin));
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
    use std::{
        alloc::{GlobalAlloc, Layout, System},
        cell::Cell as Counter,
        mem::{offset_of, size_of},
    };

    // Count only this test thread's allocation requests, never another test's
    // work. Constant TLS initialization and counter updates do not allocate.
    std::thread_local! {
        static HOST_ALLOCATIONS: Counter<Option<usize>> = const { Counter::new(None) };
    }

    struct CountingAllocator;

    fn count_host_allocation() {
        let _ = HOST_ALLOCATIONS.try_with(|count| {
            if let Some(value) = count.get() {
                count.set(Some(value + 1));
            }
        });
    }

    unsafe impl GlobalAlloc for CountingAllocator {
        unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
            count_host_allocation();
            unsafe { System.alloc(layout) }
        }
        unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
            count_host_allocation();
            unsafe { System.alloc_zeroed(layout) }
        }
        unsafe fn realloc(&self, pointer: *mut u8, layout: Layout, size: usize) -> *mut u8 {
            count_host_allocation();
            unsafe { System.realloc(pointer, layout, size) }
        }
        unsafe fn dealloc(&self, pointer: *mut u8, layout: Layout) {
            unsafe { System.dealloc(pointer, layout) }
        }
    }

    #[global_allocator]
    static TEST_ALLOCATOR: CountingAllocator = CountingAllocator;

    struct AllocationCount;
    impl Drop for AllocationCount {
        fn drop(&mut self) {
            HOST_ALLOCATIONS.with(|count| count.set(None));
        }
    }

    fn host_allocations(operation: impl FnOnce()) -> usize {
        HOST_ALLOCATIONS.with(|count| count.set(Some(0)));
        let _reset_on_unwind = AllocationCount;
        operation();
        HOST_ALLOCATIONS.with(|count| count.get().unwrap())
    }

    fn integer(value: i64) -> Value {
        Value::fixnum(value).unwrap()
    }

    fn machine(globals: u32, constants: u32) -> Vm {
        let mut vm = Vm::new(globals, constants, vec![]);
        vm.set_gc_stress(true);
        vm.state.f = 3;
        vm
    }

    fn alloc(vm: &mut Vm, value: impl SnailSchemeObject) -> Value {
        vm.runtime.allocation().alloc(value)
    }

    fn text(vm: &mut Vm, value: &str) -> Value {
        alloc(vm, Text::new(value.into()))
    }

    fn closure(vm: &mut Vm, required: usize, rest: bool, locals: usize) -> Value {
        alloc(
            vm,
            Closure {
                entry: 77,
                required,
                has_rest: rest,
                locals,
                captures: vec![],
            },
        )
    }

    fn primitive(vm: &mut Vm, name: &str) -> Value {
        alloc(vm, Primitive(primitives::Builtin::from_name(name).unwrap()))
    }

    fn arguments(vm: &mut Vm, procedure: Value, values: &[Value]) {
        let depth = vm.state.f + values.len() as u32;
        vm.reserve(depth).unwrap();
        for (index, value) in values.iter().enumerate() {
            vm.put(vm.state.f + index as u32 + 1, *value);
        }
        vm.state.s = depth;
        vm.state.c = procedure;
        vm.set_result(procedure);
    }

    #[test]
    fn numeric_fallback_roots_the_environment_and_preserves_the_frame() {
        let mut vm = machine(1, 0);
        vm.globals[0] = primitive(&mut vm, "+");
        let captured = text(&mut vm, "only reachable through the current closure");
        let environment = alloc(
            &mut vm,
            Closure {
                entry: 77,
                required: 0,
                has_rest: false,
                locals: 1,
                captures: vec![captured],
            },
        );
        vm.state.c = environment;
        vm.reserve(6).unwrap();
        vm.put(4, integer(99));
        vm.put(5, integer(1073741823));
        vm.put(6, integer(1));
        vm.state.s = 6;
        let collections = vm.gc_statistics().collections;
        vm.numeric(0).unwrap();
        assert_eq!(vm.gc_statistics().collections, collections + 1);
        assert_eq!((vm.state.f, vm.state.s, vm.state.c), (3, 4, environment));
        assert_eq!(vm.word(4), integer(99));
        assert_eq!(
            vm.single().unwrap().integer(&vm.runtime.heap).unwrap(),
            1073741824
        );
        assert_eq!(
            vm.runtime.string(captured).unwrap(),
            "only reachable through the current closure"
        );
        vm.collect();
        assert_eq!(
            vm.single().unwrap().integer(&vm.runtime.heap).unwrap(),
            1073741824
        );
    }

    #[test]
    fn register_layout_and_initial_return_frame_match_emitted_llvm() {
        let fields = [
            offset_of!(State, a),
            offset_of!(State, c),
            offset_of!(State, s),
            offset_of!(State, f),
            offset_of!(State, result_count),
            offset_of!(State, stack_end),
            offset_of!(State, capacity),
            offset_of!(State, globals),
            offset_of!(State, constants),
            offset_of!(State, argc),
            offset_of!(State, entry),
            offset_of!(State, locals),
            offset_of!(State, frames),
            offset_of!(State, max_frames),
            offset_of!(State, stopped),
        ];
        for (index, offset) in fields.into_iter().enumerate() {
            assert_eq!(offset, index * 4);
        }
        assert_eq!(size_of::<State>(), 15 * 4);
        let mut vm = Vm::new(1, 1, vec![]);
        assert_eq!((vm.state.s, vm.state.f), (3, 0));
        assert_eq!(
            [vm.word(1), vm.word(2), vm.word(3)],
            [Value::NIL, integer(0), integer(-1)]
        );
        assert_eq!(vm.state.globals, vm.globals.as_mut_ptr());
        assert_eq!(vm.state.constants, vm.constants.as_mut_ptr());
    }

    #[test]
    fn growth_preserves_active_depths_and_never_polls_gc() {
        let mut vm = machine(0, 0);
        vm.state.s = 30;
        for depth in 4..=30 {
            vm.put(depth, integer(i64::from(depth)));
        }
        let old_capacity = vm.state.capacity;
        vm.reserve(old_capacity + 1).unwrap();
        assert_eq!(vm.state.s, 30);
        assert_eq!(vm.state.f, 3);
        for depth in 4..=30 {
            assert_eq!(vm.word(depth), integer(i64::from(depth)));
        }
        assert_eq!(
            vm.state.stack_end,
            vm.stack.as_mut_ptr().wrapping_add(vm.stack.len())
        );
        let end = vm.state.stack_end;
        vm.reserve(old_capacity + 1).unwrap();
        assert_eq!(vm.state.stack_end, end);
        assert_eq!(vm.gc_statistics().collections, 0);
    }

    #[test]
    fn collection_traces_all_published_roots_but_not_inactive_stack_words() {
        let mut vm = machine(1, 1);
        let words: Vec<_> = (0..8).map(|_| text(&mut vm, "live")).collect();
        let dead = text(&mut vm, "inactive slot");
        vm.state.a = words[0];
        vm.state.c = alloc(
            &mut vm,
            Closure {
                entry: 1,
                required: 0,
                has_rest: false,
                locals: 0,
                captures: vec![words[1]],
            },
        );
        vm.globals[0] = words[2];
        vm.constants[0] = words[3];
        vm.put(4, words[4]);
        vm.put(5, words[5]);
        vm.put(6, dead);
        vm.state.s = 5;
        vm.multiple = vec![words[6], words[7]];
        vm.state.result_count = 2;
        vm.collect();
        for value in words {
            assert_eq!(vm.runtime.string(value).unwrap(), "live");
        }
        assert!(!vm.runtime.heap.contains(dead));
        assert_eq!(vm.gc_statistics().collections, 1);
    }

    #[test]
    fn nonallocating_primitive_and_fixed_closure_preparation_do_not_poll() {
        let mut vm = machine(0, 0);
        let function = closure(&mut vm, 1, false, 2);
        arguments(&mut vm, function, &[integer(9)]);
        assert_eq!(vm.prepare_apply(1).unwrap(), 0);
        assert_eq!((vm.state.entry, vm.state.locals), (77, 2));
        let car = primitive(&mut vm, "car");
        let pair = alloc(&mut vm, Pair(integer(7), Value::NIL));
        arguments(&mut vm, car, &[pair]);
        assert_eq!(vm.prepare_apply(1).unwrap(), 1);
        assert_eq!(vm.single().unwrap(), integer(7));
        assert_eq!(vm.gc_statistics().collections, 0);
    }

    #[test]
    fn warmed_fixed_arity_preparation_allocates_neither_host_nor_managed_objects() {
        let mut vm = machine(0, 0);
        let function = closure(&mut vm, 2, false, 4);
        arguments(&mut vm, function, &[integer(1), integer(2)]);
        assert_eq!(vm.prepare_apply(2).unwrap(), 0);
        let allocated = vm.gc_statistics().allocated;
        let count = host_allocations(|| {
            for _ in 0..10_000 {
                assert_eq!(vm.prepare_apply(2).unwrap(), 0);
            }
        });
        assert_eq!(count, 0);
        assert_eq!(vm.gc_statistics().allocated, allocated);
        assert_eq!(vm.gc_statistics().collections, 0);
    }

    #[test]
    fn warmed_nonallocating_primitive_arguments_do_not_allocate_a_host_vector() {
        let mut vm = machine(0, 0);
        let car = primitive(&mut vm, "car");
        let pair = alloc(&mut vm, Pair(integer(7), Value::NIL));
        arguments(&mut vm, car, &[pair]);
        assert_eq!(vm.prepare_apply(1).unwrap(), 1);
        let count = host_allocations(|| {
            for _ in 0..10_000 {
                assert_eq!(vm.prepare_apply(1).unwrap(), 1);
            }
        });
        assert_eq!(count, 0);
        assert_eq!(vm.gc_statistics().collections, 0);
    }

    #[test]
    fn allocating_primitive_polls_with_arguments_published() {
        let mut vm = machine(0, 0);
        let cons = primitive(&mut vm, "cons");
        let child = text(&mut vm, "rooted argument");
        arguments(&mut vm, cons, &[child, Value::NIL]);
        assert_eq!(vm.prepare_apply(2).unwrap(), 1);
        assert_eq!(vm.gc_statistics().collections, 1);
        vm.state.s = vm.state.f;
        vm.collect();
        let pair = vm.runtime.heap.get::<Pair>(vm.single().unwrap()).unwrap();
        assert_eq!(vm.runtime.string(pair.0).unwrap(), "rooted argument");
    }

    #[test]
    fn allocation_burst_keeps_detached_rust_temporaries_until_publication() {
        let mut vm = machine(0, 0);
        let child = text(&mut vm, "detached temporary");
        let parent = alloc(&mut vm, Pair(child, Value::NIL));
        vm.set_result(parent);
        let result = {
            let mut allocation = vm.allocation([]);
            allocation.heap.get_mut::<Pair>(parent).unwrap().0 = Value::NIL;
            for _ in 0..2048 {
                allocation.alloc(Pair(Value::NIL, Value::NIL));
            }
            assert_eq!(allocation.gc_statistics().collections, 1);
            allocation.alloc(Pair(child, Value::NIL))
        };
        assert_eq!(vm.gc_statistics().collections, 1);
        vm.set_result(result);
        vm.collect();
        let child = vm.runtime.heap.get::<Pair>(result).unwrap().0;
        assert_eq!(vm.runtime.string(child).unwrap(), "detached temporary");
    }

    #[test]
    fn boxed_locals_and_closures_share_one_mutable_location() {
        let mut vm = machine(0, 0);
        let initial = text(&mut vm, "initial local");
        arguments(&mut vm, Value::NIL, &[initial]);
        vm.box_local(0).unwrap();
        let cell = vm.word(4);
        vm.put(5, cell);
        vm.state.s = 5;
        vm.close(10, 0, false, 0, 1).unwrap();
        vm.state.c = vm.single().unwrap();
        let replacement = text(&mut vm, "assigned through closure");
        let captured = unsafe { *vm.free_slot(0).unwrap() };
        assert_eq!(captured, cell);
        unsafe {
            *vm.cell_slot(captured).unwrap() = replacement;
        }
        vm.collect();
        let value = vm.runtime.heap.get::<Cell>(vm.word(4)).unwrap().0;
        assert_eq!(
            vm.runtime.string(value).unwrap(),
            "assigned through closure"
        );
    }

    #[test]
    fn immutable_closure_captures_do_not_allocate_binding_cells() {
        let mut vm = machine(0, 0);
        let retained = text(&mut vm, "direct capture");
        arguments(&mut vm, Value::NIL, &[retained]);
        let allocated = vm.gc_statistics().allocated;
        vm.close(10, 0, false, 0, 1).unwrap();
        assert_eq!(vm.gc_statistics().allocated, allocated + 1);
        assert_eq!(vm.state.s, 3);
        vm.collect();
        let function = vm
            .runtime
            .heap
            .get::<Closure>(vm.single().unwrap())
            .unwrap();
        assert_eq!(function.captures, vec![retained]);
        assert_eq!(vm.runtime.string(retained).unwrap(), "direct capture");
    }

    #[test]
    fn rest_arguments_are_rooted_and_packed_in_source_order() {
        let mut vm = machine(0, 0);
        let function = closure(&mut vm, 1, true, 2);
        let first = text(&mut vm, "first");
        let second = text(&mut vm, "second");
        arguments(&mut vm, function, &[integer(7), first, second]);
        let allocated = vm.gc_statistics().allocated;
        assert_eq!(vm.prepare_apply(3).unwrap(), 0);
        assert_eq!(vm.state.s, 5);
        assert_eq!(vm.word(4), integer(7));
        assert_eq!(
            vm.runtime.list_values(vm.word(5)).unwrap(),
            vec![first, second]
        );
        assert_eq!(vm.gc_statistics().allocated, allocated + 2);
        vm.collect();
        assert_eq!(vm.runtime.string(second).unwrap(), "second");
        arguments(&mut vm, function, &[integer(8)]);
        assert_eq!(vm.prepare_apply(1).unwrap(), 0);
        assert_eq!(vm.word(5), Value::NIL);
    }

    #[test]
    fn apply_replaces_only_its_argument_area() {
        let mut vm = machine(0, 0);
        let function = closure(&mut vm, 3, false, 3);
        let apply = primitive(&mut vm, "apply");
        let rest = vm.runtime.allocation().list(&[integer(2), integer(3)]);
        arguments(&mut vm, apply, &[function, integer(1), rest]);
        assert_eq!(vm.prepare_apply(3).unwrap(), 2);
        assert_eq!(vm.single().unwrap(), function);
        assert_eq!((vm.state.f, vm.state.s, vm.state.argc), (3, 6, 3));
        assert_eq!(
            [vm.word(4), vm.word(5), vm.word(6)],
            [integer(1), integer(2), integer(3)]
        );
        assert_eq!(vm.word(3), integer(-1));
    }

    #[test]
    fn values_consumer_and_heap_results_survive_growth_and_collection() {
        let mut vm = machine(0, 0);
        let consumer = closure(&mut vm, 300, false, 300);
        let value = text(&mut vm, "many results");
        vm.put(4, Value::NIL);
        vm.put(5, consumer);
        vm.state.s = 5;
        vm.multiple = vec![value; 300];
        vm.state.result_count = 300;
        vm.collect();
        vm.receive().unwrap();
        assert_eq!(vm.single().unwrap(), consumer);
        assert_eq!((vm.state.s, vm.state.argc), (303, 300));
        assert_eq!(vm.gc_statistics().collections, 1);
        vm.collect();
        assert_eq!(vm.word(303), value);
        assert_eq!(vm.runtime.string(value).unwrap(), "many results");
    }

    #[test]
    fn values_preserve_zero_one_and_many_results_without_host_control_recursion() {
        let mut vm = machine(0, 0);
        let values = primitive(&mut vm, "values");
        for count in [0, 1, 3] {
            let args = [integer(1), integer(2), integer(3)];
            arguments(&mut vm, values, &args[..count]);
            assert_eq!(vm.prepare_apply(count as u32).unwrap(), 1);
            assert_eq!(vm.results(), &args[..count]);
        }
        assert_eq!(vm.gc_statistics().collections, 0);
    }

    fn capture_nested_frame(vm: &mut Vm, cell: Value, local: Value) -> Value {
        for (depth, value) in [cell, local, Value::NIL, integer(3), integer(99)]
            .into_iter()
            .enumerate()
        {
            vm.put(depth as u32 + 4, value);
        }
        vm.state.f = 8;
        vm.state.s = 8;
        vm.state.frames = 2;
        vm.capture().unwrap();
        vm.single().unwrap()
    }

    #[test]
    fn snapshots_remain_reusable_after_growth_and_share_mutated_cells() {
        let mut vm = machine(1, 0);
        let cell = alloc(&mut vm, Cell(integer(1)));
        let local = text(&mut vm, "snapshot-only local");
        let saved = capture_nested_frame(&mut vm, cell, local);
        vm.globals[0] = saved;
        let original = vm
            .runtime
            .heap
            .get::<Continuation>(saved)
            .unwrap()
            .stack
            .clone();
        vm.state.f = 3;
        vm.state.s = 3;
        vm.set_result(Value::UNSPECIFIED);
        vm.collect();
        vm.reserve(1000).unwrap();
        for number in [2, 3] {
            vm.runtime.heap.get_mut::<Cell>(cell).unwrap().0 = integer(number);
            vm.state.f = 3;
            arguments(&mut vm, saved, &[integer(number + 10)]);
            let collections = vm.gc_statistics().collections;
            vm.restore(1).unwrap();
            assert_eq!(vm.single().unwrap(), integer(number + 10));
            assert_eq!((vm.state.f, vm.state.s, vm.state.frames), (8, 8, 2));
            assert_eq!(vm.word(4), cell);
            assert_eq!(
                vm.runtime.heap.get::<Cell>(cell).unwrap().0,
                integer(number)
            );
            assert_eq!(
                vm.runtime.string(vm.word(5)).unwrap(),
                "snapshot-only local"
            );
            assert_eq!(vm.gc_statistics().collections, collections);
            vm.put(5, integer(999));
            assert_eq!(
                vm.runtime.heap.get::<Continuation>(saved).unwrap().stack,
                original
            );
        }
    }

    #[test]
    fn snapshots_preserve_pending_frame_counts_and_the_execution_high_water_mark() {
        let mut vm = machine(1, 0);
        // The outer application is pending while its operand invokes call/cc.
        // Both headers save f=3, so following f skips the pending header at 6.
        for base in [6, 9] {
            vm.put(base - 2, Value::NIL);
            vm.put(base - 1, integer(3));
            vm.put(base, integer(99));
        }
        vm.state.f = 9;
        vm.state.s = 9;
        vm.state.frames = 3;
        vm.capture().unwrap();
        let saved = vm.single().unwrap();
        vm.globals[0] = saved;
        vm.state.max_frames = 10;
        for _ in 0..2 {
            vm.state.f = 3;
            vm.state.frames = 1;
            arguments(&mut vm, saved, &[]);
            vm.restore(0).unwrap();
            assert_eq!((vm.state.f, vm.state.s, vm.state.frames), (9, 9, 3));
            assert_eq!(vm.state.max_frames, 10);
        }
    }

    #[test]
    fn continuation_restore_preserves_zero_and_multiple_incoming_values() {
        let mut vm = machine(1, 0);
        vm.capture().unwrap();
        let saved = vm.single().unwrap();
        vm.globals[0] = saved;
        for count in [0, 1, 3] {
            let values = [integer(4), integer(5), integer(6)];
            arguments(&mut vm, saved, &values[..count]);
            assert_eq!(vm.prepare_apply(count as u32).unwrap(), 5);
            vm.restore(count as u32).unwrap();
            assert_eq!(vm.results(), &values[..count]);
            assert_eq!((vm.state.f, vm.state.s), (3, 3));
        }
    }

    #[test]
    fn collection_budget_and_symbol_identity_survive_the_stack_change() {
        let mut vm = machine(0, 0);
        vm.set_gc_stress(false);
        let symbol = vm.runtime.intern("permanent symbol");
        for _ in 0..2048 {
            alloc(&mut vm, Pair(Value::NIL, Value::NIL));
        }
        let _allocation = vm.allocation([]);
        assert_eq!(vm.gc_statistics().collections, 1);
        assert_eq!(vm.runtime.heap.live_objects(), 3);
        assert_eq!(vm.runtime.intern("permanent symbol"), symbol);
        assert_eq!(vm.runtime.symbol_name(symbol).unwrap(), "permanent symbol");
    }

    #[test]
    fn first_failure_halts_later_abi_services() {
        let mut vm = machine(0, 0);
        let capacity = vm.state.capacity;
        unsafe {
            crate::snail_rt_uninitialized(&mut vm);
            crate::snail_rt_reserve(&mut vm, capacity * 2);
            assert_eq!(crate::snail_rt_prepare_apply(&mut vm, 0), 255);
        }
        vm.fail("later error".into());
        assert_eq!(vm.error(), Some("read of an uninitialized binding"));
        assert_eq!(vm.state.capacity, capacity);
        assert_eq!(vm.exit_code(), 1);
    }
}
