use super::*;

#[path = "compiler_blocks.rs"]
mod blocks;

#[path = "compiler_asm.rs"]
mod asm;

pub(super) fn asm_probe(directives: &Datum) -> Datum {
    asm::probe(directives)
}
use r7rs_wasm_reference::read_all;
use std::collections::VecDeque;

// ---- Persistent target procedure descriptions ----

#[derive(Clone)]
enum Specialization {
    Identity,
    Safe(usize),
    Unsafe(usize),
    Arithmetic {
        fix_safe: bool,
        fix: usize,
        flonum: usize,
    },
}
struct Primitive {
    name: String,
    key: String,
    pattern: Datum,
    side_effects: bool,
    strict: Datum,
    result_type: Datum,
    inline_effects: Option<bool>,
    test: bool,
    specialization: Specialization,
}
#[allow(clippy::vec_box)]
pub(super) struct Catalog {
    procedures: Vec<Box<Primitive>>,
    common: Vec<String>,
    r4rs: Vec<String>,
    multilisp: Vec<String>,
}
fn description_rows(text: &str) -> Vec<Datum> {
    read_all(text)[0].list().to_vec()
}
fn procedure_names(text: &str) -> Vec<String> {
    description_rows(text)
        .iter()
        .map(|row| match row {
            Datum::List(values) | Datum::Dotted(values, _) => values[0].atom().to_lowercase(),
            _ => panic!("invalid standard-procedure description"),
        })
        .collect()
}
fn pattern_member(n: usize, pattern: &Datum) -> bool {
    match pattern {
        Datum::List(values) => values.iter().any(|value| value.number() == n),
        Datum::Dotted(values, tail) => {
            values.iter().any(|value| value.number() == n) || pattern_member(n, tail)
        }
        Datum::Atom(_) => pattern.number() <= n,
        _ => panic!("invalid target argument pattern"),
    }
}
impl Catalog {
    pub(super) fn new() -> Self {
        let rows = description_rows(include_str!("compiler-prim-procs.scm"));
        let mut procedures = Vec::new();
        for row in rows {
            let fields = row.list();
            assert_eq!(fields.len(), 5);
            procedures.push(Box::new(Primitive {
                name: fields[0].atom().to_owned(),
                key: fields[0].atom().to_lowercase(),
                pattern: fields[1].clone(),
                side_effects: fields[2].atom() == "#t",
                strict: fields[3].clone(),
                result_type: fields[4].clone(),
                inline_effects: None,
                test: false,
                specialization: Specialization::Identity,
            }));
        }
        let mut catalog = Self {
            procedures,
            common: procedure_names(include_str!("compiler-common-procedures.scm")),
            r4rs: procedure_names(include_str!("compiler-r4rs-scheme-specific-procedures.scm")),
            multilisp: procedure_names(include_str!("compiler-multilisp-specific-procedures.scm")),
        };
        for recipe in description_rows(include_str!("compiler-primitive-recipes.scm")) {
            catalog.install_recipe(recipe.list());
        }
        catalog
    }
    fn lookup(&self, name: &str) -> usize {
        let key = name.to_lowercase();
        self.procedures
            .iter()
            .position(|procedure| procedure.key == key)
            .unwrap_or_else(|| panic!("unknown target procedure {name}"))
    }
    fn install_recipe(&mut self, fields: &[Datum]) {
        let id = self.lookup(fields[1].atom());
        match fields[0].atom() {
            "apply" => self.procedures[id].inline_effects = Some(fields[2].atom() == "#t"),
            "ifjump" => {
                self.procedures[id].inline_effects = Some(false);
                self.procedures[id].test = true;
            }
            "specialize" => {
                self.procedures[id].specialization = self.specializer(id, fields[2].list())
            }
            _ => panic!("invalid compiler target recipe"),
        }
    }
    fn specializer(&self, receiver: usize, fields: &[Datum]) -> Specialization {
        match fields[0].atom() {
            "safe" => Specialization::Safe(self.lookup(fields[1].atom())),
            "unsafe" => Specialization::Unsafe(self.lookup(fields[1].atom())),
            "safe-arith" | "unsafe-arith" => Specialization::Arithmetic {
                fix_safe: fields[0].atom() == "safe-arith",
                fix: if fields[1].atom() == "#f" {
                    receiver
                } else {
                    self.lookup(fields[1].atom())
                },
                flonum: if fields[2].atom() == "#f" {
                    receiver
                } else {
                    self.lookup(fields[2].atom())
                },
            },
            _ => panic!("invalid primitive specialization recipe"),
        }
    }
    fn standard(&self, syntax: &Compiler<'_>, env: usize, name: &str) -> bool {
        let dialect = syntax.declaration(env, "dialect", None, atom("ieee-scheme"));
        self.common.iter().any(|candidate| candidate == name)
            || match dialect.atom() {
                "r4rs-scheme" => self.r4rs.iter().any(|candidate| candidate == name),
                "multilisp" => self.multilisp.iter().any(|candidate| candidate == name),
                _ => false,
            }
    }
    fn bound_primitive(&self, syntax: &Compiler<'_>, env: usize, name: &str) -> Option<usize> {
        let declaration = if self.standard(syntax, env, name) {
            "standard-bindings"
        } else {
            "extended-bindings"
        };
        if syntax
            .declaration(env, declaration, Some(name), atom("#f"))
            .atom()
            == "#f"
        {
            return None;
        }
        self.procedures
            .iter()
            .position(|primitive| primitive.key == name)
    }
    fn specialize(&self, syntax: &Compiler<'_>, env: usize, receiver: usize) -> usize {
        let safe = syntax.declaration(env, "safe", None, atom("#f")).atom() != "#f";
        match self.procedures[receiver].specialization {
            Specialization::Identity => receiver,
            Specialization::Safe(target) => target,
            Specialization::Unsafe(target) => {
                if safe {
                    receiver
                } else {
                    target
                }
            }
            Specialization::Arithmetic {
                fix_safe,
                fix,
                flonum,
            } => match syntax
                .declaration(
                    env,
                    "arith",
                    Some(&self.procedures[receiver].key),
                    atom("generic"),
                )
                .atom()
            {
                "fixnum" if fix_safe || !safe => fix,
                "flonum" if !safe => flonum,
                _ => receiver,
            },
        }
    }
    fn boolean(&self, procedure: usize) -> bool {
        let result = &self.procedures[procedure].result_type;
        let kind = match result {
            Datum::List(values) if !values.is_empty() => &values[0],
            Datum::Dotted(values, _) if !values.is_empty() => &values[0],
            _ => result,
        };
        matches!(kind, Datum::Atom(name) if name == "boolean")
    }
}

// ---- Virtual operands and their original linear interning table ----

#[derive(Clone)]
enum Object {
    Literal(Rc<Datum>),
    Primitive(usize),
    Procedure(usize),
}
fn object_eqv(first: &Object, second: &Object) -> bool {
    match (first, second) {
        (Object::Primitive(a), Object::Primitive(b))
        | (Object::Procedure(a), Object::Procedure(b)) => a == b,
        (Object::Literal(a), Object::Literal(b)) => {
            if Rc::ptr_eq(a, b) {
                return true;
            }
            match (&**a, &**b) {
                (Datum::Atom(a), Datum::Atom(b)) => a == b,
                (Datum::Character(a), Datum::Character(b)) => a == b,
                (Datum::List(a), Datum::List(b)) if a.is_empty() && b.is_empty() => true,
                _ => false,
            }
        }
        _ => false,
    }
}
#[derive(Clone)]
enum OperandEntry {
    Global(String),
    Closure { base: usize, index: usize },
    Object(Object),
}
fn operand_entry_eqv(first: &OperandEntry, second: &OperandEntry) -> bool {
    match (first, second) {
        (OperandEntry::Global(a), OperandEntry::Global(b)) => a == b,
        (
            OperandEntry::Closure { base: a, index: b },
            OperandEntry::Closure { base: c, index: d },
        ) => a == c && b == d,
        (OperandEntry::Object(a), OperandEntry::Object(b)) => object_eqv(a, b),
        _ => false,
    }
}
pub(super) struct OperandTable {
    // All 10,000 slots are initialized inside each compilation, as in virtual.begin!.
    entries: Box<[Option<Box<OperandEntry>>]>,
    used: usize,
}
impl OperandTable {
    pub(super) fn new() -> Self {
        Self {
            entries: (0..10_000)
                .map(|_| None)
                .collect::<Vec<_>>()
                .into_boxed_slice(),
            used: 0,
        }
    }
    fn intern(&mut self, entry: OperandEntry) -> usize {
        for i in 0..self.used {
            if operand_entry_eqv(self.entries[i].as_deref().unwrap(), &entry) {
                return i;
            }
        }
        assert!(self.used < 10_000, "virtual operand table overflow");
        let id = self.used;
        self.used += 1;
        self.entries[id] = Some(Box::new(entry));
        id
    }
    fn global(&mut self, name: &str) -> usize {
        30_000 + self.intern(OperandEntry::Global(name.to_owned()))
    }
    fn closure(&mut self, base: usize, index: usize) -> usize {
        40_000 + self.intern(OperandEntry::Closure { base, index })
    }
    fn object(&mut self, object: Object) -> usize {
        50_000 + self.intern(OperandEntry::Object(object))
    }
    fn entry(&self, operand: usize) -> &OperandEntry {
        self.entries[operand % 10_000].as_deref().unwrap()
    }
    fn contains(&self, first: usize, second: usize) -> bool {
        if first == second {
            return true;
        }
        match self.entry_if_closure(second) {
            Some((base, _)) => self.contains(first, base),
            None => false,
        }
    }
    fn entry_if_closure(&self, operand: usize) -> Option<(usize, usize)> {
        if operand / 10_000 != 4 {
            return None;
        }
        let OperandEntry::Closure { base, index } = self.entry(operand) else {
            unreachable!()
        };
        Some((*base, *index))
    }
}
fn register(operand: usize) -> bool {
    operand < 10_000
}
fn stack(operand: usize) -> bool {
    operand / 10_000 == 1
}
fn label(number: usize) -> usize {
    20_000 + number
}
fn stack_slot(number: usize) -> usize {
    10_000 + number
}

// ---- Saved frame contents and polling constraints ----

#[derive(Clone, Copy)]
struct Poll {
    since_entry: bool,
    delta: usize,
}
impl Poll {
    fn entry() -> Self {
        Self {
            since_entry: false,
            delta: 75,
        }
    }
    fn returned(self) -> Self {
        Self {
            since_entry: self.since_entry,
            delta: 15 + self.delta.max(15),
        }
    }
    fn merge(self, second: Self) -> Self {
        Self {
            since_entry: self.since_entry || second.since_entry,
            delta: self.delta.max(second.delta),
        }
    }
}
#[derive(Clone)]
struct Context {
    size: usize,
    slots: Ids,
    registers: Ids,
    closed: Ids,
    poll: Poll,
    entry_block: Option<usize>,
}
#[derive(Clone)]
struct Frame {
    size: usize,
    slots: Ids,
    registers: Ids,
    closed: Ids,
    live: Ids,
}
impl Context {
    fn frame(&self, live: Ids) -> Rc<Frame> {
        Rc::new(Frame {
            size: self.size,
            slots: self.slots.clone(),
            registers: self.registers.clone(),
            closed: self.closed.clone(),
            live,
        })
    }
}
#[derive(Clone, Copy)]
struct Specials {
    return_var: usize,
    closure_var: usize,
    empty_var: usize,
}

// ---- Concrete instruction and basic-block graphs ----

#[derive(Clone, PartialEq, Eq)]
enum LabelKind {
    Simple,
    Entry {
        parameters: usize,
        minimum: usize,
        rest: bool,
        closed: bool,
    },
    Return,
    TaskEntry,
    TaskReturn,
}
#[derive(Clone)]
struct ClosureParameters {
    destination: usize,
    label: usize,
    operands: Ids,
}
// Closure records remain separately allocated as in the source graph.
#[derive(Clone)]
#[allow(clippy::vec_box)]
enum InstructionKind {
    Label {
        number: usize,
        kind: LabelKind,
    },
    Apply {
        primitive: usize,
        operands: Ids,
        destination: Option<usize>,
    },
    Copy {
        operand: usize,
        destination: usize,
    },
    Close(Vec<Box<ClosureParameters>>),
    IfJump {
        test: usize,
        operands: Ids,
        true_label: usize,
        false_label: usize,
        poll: bool,
    },
    Jump {
        operand: usize,
        arguments: Option<usize>,
        poll: bool,
    },
}
struct Instruction {
    kind: InstructionKind,
    frame: Rc<Frame>,
    source: Option<usize>,
}
struct BasicBlock {
    label: usize,
    instructions: VecDeque<usize>,
    branch: Option<usize>,
    references: Ids,
    precedents: Ids,
}
struct Blocks {
    next_label: usize,
    blocks: VecDeque<usize>,
    entry: usize,
}
struct CompiledProcedure {
    name: String,
    primitive: bool,
    blocks: Option<usize>,
    pattern: Datum,
}
struct ScheduledProcedure {
    node: usize,
    block: usize,
    context: Context,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum Why {
    Tail,
    Need,
    Keep,
    Side,
}

// Association lists allocate both the mutable key/value pair and its list cell.
// A temporary replacement keeps that pair rooted while new prefixes are added.
#[derive(Clone, Default)]
struct Bindings(Option<Rc<BindingLink>>);
struct BindingLink {
    pair: Rc<BindingPair>,
    next: Bindings,
}
struct BindingPair {
    key: usize,
    value: std::cell::Cell<usize>,
}
impl Bindings {
    fn add(&mut self, key: usize, value: usize) {
        *self = Self(Some(Rc::new(BindingLink {
            pair: Rc::new(BindingPair {
                key,
                value: std::cell::Cell::new(value),
            }),
            next: self.clone(),
        })));
    }
    fn get(&self, key: usize) -> Option<Rc<BindingPair>> {
        let mut cursor = self;
        while let Some(link) = &cursor.0 {
            if link.pair.key == key {
                return Some(link.pair.clone());
            }
            cursor = &link.next;
        }
        None
    }
    fn keys(&self) -> Ids {
        match &self.0 {
            None => Ids::default(),
            Some(link) => Ids::cons(link.pair.key, link.next.keys()),
        }
    }
}
#[allow(clippy::vec_box)]
struct Generator<'s, 'a> {
    syntax: &'s mut Compiler<'a>,
    catalog: &'s Catalog,
    operands: OperandTable,
    instructions: Vec<Box<Instruction>>,
    blocks: Vec<Box<BasicBlock>>,
    groups: Vec<Box<Blocks>>,
    procedures: Vec<Box<CompiledProcedure>>,
    current_group: usize,
    current_block: usize,
    context: Context,
    specials: Specials,
    constants: Bindings,
    known: Bindings,
    scheduled: Vec<Box<ScheduledProcedure>>,
    purify_blocks: bool,
}
impl<'s, 'a> Generator<'s, 'a> {
    fn new(
        syntax: &'s mut Compiler<'a>,
        catalog: &'s Catalog,
        operands: OperandTable,
        specials: Specials,
    ) -> Self {
        let context = Context {
            size: 0,
            slots: Ids::default(),
            registers: Ids::from_slice(&[specials.return_var]),
            closed: Ids::default(),
            poll: Poll::entry(),
            entry_block: None,
        };
        Self {
            syntax,
            catalog,
            operands,
            specials,
            instructions: vec![],
            blocks: vec![],
            groups: vec![],
            procedures: vec![],
            current_group: 0,
            current_block: 0,
            context,
            constants: Bindings::default(),
            known: Bindings::default(),
            scheduled: vec![],
            purify_blocks: false,
        }
    }
    fn instruction(
        &mut self,
        kind: InstructionKind,
        frame: Rc<Frame>,
        source: Option<usize>,
    ) -> usize {
        let id = self.instructions.len();
        self.instructions.push(Box::new(Instruction {
            kind,
            frame,
            source,
        }));
        id
    }
    fn new_group(&mut self) -> usize {
        let id = self.groups.len();
        self.groups.push(Box::new(Blocks {
            next_label: 1,
            blocks: VecDeque::new(),
            entry: 0,
        }));
        id
    }
    fn new_label(&mut self) -> usize {
        let group = &mut self.groups[self.current_group];
        assert!(group.next_label < 9999, "procedure label limit");
        let result = group.next_label;
        group.next_label += 1;
        result
    }
    fn new_block(&mut self, instruction: usize) -> usize {
        let id = self.blocks.len();
        self.blocks.push(Box::new(BasicBlock {
            label: instruction,
            instructions: VecDeque::new(),
            branch: None,
            references: Ids::default(),
            precedents: Ids::default(),
        }));
        self.groups[self.current_group].blocks.push_back(id);
        id
    }
    fn block_label(&self, block: usize) -> usize {
        let InstructionKind::Label { number, .. } =
            self.instructions[self.blocks[block].label].kind
        else {
            unreachable!()
        };
        number
    }
    fn label_block(&self, number: usize) -> usize {
        self.groups[self.current_group]
            .blocks
            .iter()
            .copied()
            .find(|&block| self.block_label(block) == number)
            .expect("label must have a block")
    }
    fn append(&mut self, kind: InstructionKind, live: Ids, source: Option<usize>) {
        let instruction = self.instruction(kind, self.context.frame(live), source);
        self.blocks[self.current_block]
            .instructions
            .push_back(instruction);
    }
    fn branch(&mut self, kind: InstructionKind, live: Ids, source: Option<usize>) {
        let instruction = self.instruction(kind, self.context.frame(live), source);
        self.blocks[self.current_block].branch = Some(instruction);
    }
    fn temporary(&mut self, name: &str) -> usize {
        self.syntax.variable(usize::MAX, name, Binding::Temporary)
    }
    fn live_variables(&self, live: &Ids) -> Ids {
        if live.intersection(&self.context.closed).empty() {
            live.clone()
        } else {
            live.adjoin(self.specials.closure_var)
        }
    }
    fn live_slots(&self, live: &Ids) -> Ids {
        let live = self.live_variables(live);
        let slots: Vec<_> = self
            .context
            .slots
            .values()
            .into_iter()
            .enumerate()
            .filter(|(_, var)| live.has(*var))
            .map(|(i, _)| self.context.size - i)
            .collect();
        Ids::from_slice(&slots)
    }
    fn dead_slots(&self, live: &Ids) -> Ids {
        let live = self.live_variables(live);
        let slots: Vec<_> = self
            .context
            .slots
            .values()
            .into_iter()
            .enumerate()
            .filter(|(_, var)| !live.has(*var))
            .map(|(i, _)| self.context.size - i)
            .collect();
        Ids::from_slice(&slots)
    }
    fn live_registers(&self, live: &Ids) -> Ids {
        let live = self.live_variables(live);
        let registers: Vec<_> = self
            .context
            .registers
            .values()
            .into_iter()
            .enumerate()
            .filter(|(_, var)| live.has(*var) && !self.context.slots.has(*var))
            .map(|(i, _)| i)
            .collect();
        Ids::from_slice(&registers)
    }
    fn dead_registers(&self, live: &Ids) -> Ids {
        let live = self.live_variables(live);
        let registers = self.context.registers.values();
        let dead: Vec<_> = (0..5)
            .filter(|&i| {
                registers
                    .get(i)
                    .is_none_or(|var| !live.has(*var) || self.context.slots.has(*var))
            })
            .collect();
        Ids::from_slice(&dead)
    }
    fn highest_live_slot(&self, live: &Ids) -> usize {
        stack_slot(
            self.live_slots(live)
                .values()
                .into_iter()
                .max()
                .unwrap_or(0),
        )
    }
    fn lowest_dead_slot(&self, live: &Ids) -> usize {
        stack_slot(
            self.dead_slots(live)
                .values()
                .into_iter()
                .min()
                .unwrap_or(self.context.size + 1),
        )
    }
    fn lowest_dead_register(&self, live: &Ids) -> Option<usize> {
        self.dead_registers(live)
            .remove(0)
            .values()
            .into_iter()
            .min()
    }
    fn highest_dead_register(&self, live: &Ids) -> Option<usize> {
        self.dead_registers(live).values().into_iter().max()
    }
    fn push_slot(&mut self) {
        self.context.size += 1;
        self.context.slots = Ids::cons(self.specials.empty_var, self.context.slots.clone());
    }
    fn deallocate(&mut self, number: usize) {
        assert!(number <= self.context.size);
        self.context.size -= number;
        self.context.slots = ids_suffix(&self.context.slots, number);
    }
    fn variable_operand(&mut self, variable: usize) -> Option<usize> {
        if let Some(pair) = self.constants.get(variable) {
            return Some(pair.value.get());
        }
        if self.syntax.variables[variable].binding == Binding::Global {
            return Some(self.operands.global(&self.syntax.variables[variable].name));
        }
        if let Some(index) = ids_position(&self.context.registers, variable) {
            return Some(index);
        }
        if let Some(index) = ids_position(&self.context.slots, variable) {
            return Some(stack_slot(self.context.size - index));
        }
        if let Some(index) = ids_position(&self.context.closed, variable) {
            let base = self
                .variable_operand(self.specials.closure_var)
                .expect("accessible closure environment");
            return Some(self.operands.closure(base, index + 1));
        }
        None
    }
    fn operand_variable(&mut self, operand: usize) -> usize {
        match operand / 10_000 {
            0 => ids_nth(&self.context.registers, operand).expect("accessible register"),
            1 => ids_nth(&self.context.slots, self.context.size - operand % 10_000)
                .expect("accessible stack slot"),
            3 => {
                let OperandEntry::Global(name) = self.operands.entry(operand) else {
                    unreachable!()
                };
                let name = name.clone();
                self.syntax
                    .lookup(self.syntax.global, &name, usize::MAX, false)
            }
            _ => panic!("operand must identify a variable location"),
        }
    }
    fn put_variable(&mut self, operand: usize, variable: usize) {
        if variable == self.specials.return_var {
            if let Some(old) = self.variable_operand(variable) {
                self.replace_location(old, self.specials.empty_var);
            }
        }
        self.replace_location(operand, variable);
    }
    fn replace_location(&mut self, operand: usize, variable: usize) {
        if register(operand) {
            self.context.registers = ids_replace(
                &self.context.registers,
                operand,
                variable,
                self.specials.empty_var,
            );
        } else if stack(operand) {
            self.context.slots = ids_replace(
                &self.context.slots,
                self.context.size - operand % 10_000,
                variable,
                self.specials.empty_var,
            );
        } else {
            panic!("variable destination must be a register or slot");
        }
    }
    fn copy(
        &mut self,
        operand: usize,
        destination: usize,
        variable: Option<usize>,
        live: &Ids,
        source: Option<usize>,
    ) {
        if stack(destination) && destination % 10_000 > self.context.size {
            self.push_slot();
        }
        if let Some(variable) = variable {
            self.put_variable(destination, variable);
        }
        if operand == destination {
            return;
        }
        let live = match variable {
            Some(variable) => live.adjoin(variable),
            None => live.clone(),
        };
        self.append(
            InstructionKind::Copy {
                operand,
                destination,
            },
            live,
            source,
        );
    }
    fn contained_location(&self, operand: usize) -> Option<usize> {
        if register(operand) || stack(operand) {
            return Some(operand);
        }
        self.operands
            .entry_if_closure(operand)
            .and_then(|(base, _)| self.contained_location(base))
    }
    fn operand_needed(&mut self, operand: usize, live: &Ids) -> Ids {
        match self.contained_location(operand) {
            Some(location) => live.adjoin(self.operand_variable(location)),
            None => live.clone(),
        }
    }
    fn save_operand(&mut self, operand: usize, live: &Ids, source: Option<usize>) {
        let slot = self.lowest_dead_slot(live);
        let variable = self.operand_variable(operand);
        self.copy(operand, slot, Some(variable), live, source);
    }
    fn save_registers(&mut self, registers: &Ids, live: &Ids, source: Option<usize>) {
        for register in registers.values() {
            self.save_operand(register, live, source);
        }
    }
    fn save_to_register(
        &mut self,
        operand: usize,
        destination: usize,
        variable: usize,
        live: &Ids,
        source: Option<usize>,
    ) {
        if self.live_registers(live).has(destination) {
            let needed = self.operand_needed(operand, live);
            self.save_operand(destination, &needed, source);
        }
        self.copy(operand, destination, Some(variable), live, source);
    }
    fn save_to_slot(
        &mut self,
        operand: usize,
        destination: usize,
        variable: usize,
        live: &Ids,
        source: Option<usize>,
    ) {
        if self.live_slots(live).has(destination % 10_000) {
            let needed = self.operand_needed(operand, live);
            self.save_operand(destination, &needed, source);
        }
        self.copy(operand, destination, Some(variable), live, source);
    }
    fn save_in_slot(&mut self, operand: usize, variable: usize, live: &Ids, source: Option<usize>) {
        self.copy(
            operand,
            self.lowest_dead_slot(live),
            Some(variable),
            live,
            source,
        );
    }
    fn save_value(&mut self, operand: usize, variable: usize, live: &Ids, source: Option<usize>) {
        match operand / 10_000 {
            2 | 5 => self.constants.add(variable, operand),
            0 if !self.live_registers(live).has(operand) => self.put_variable(operand, variable),
            1 if !self.live_slots(live).has(operand % 10_000) => {
                self.put_variable(operand, variable)
            }
            _ => self.save_in_slot(operand, variable, live, source),
        }
    }
    fn save_argument(
        &mut self,
        operand: usize,
        variable: usize,
        live: &Ids,
        source: Option<usize>,
    ) {
        if operand / 10_000 == 3 {
            self.constants.add(variable, operand);
        } else {
            self.save_value(operand, variable, live, source);
        }
    }
    fn save_variable(
        &mut self,
        operand: usize,
        variable: usize,
        live: &Ids,
        source: Option<usize>,
    ) -> usize {
        match operand / 10_000 {
            2 | 5 => {
                self.constants.add(variable, operand);
                variable
            }
            0 | 1 | 3 => self.operand_variable(operand),
            _ => {
                let destination = self
                    .highest_dead_register(live)
                    .unwrap_or_else(|| self.lowest_dead_slot(live));
                self.copy(operand, destination, Some(variable), live, source);
                variable
            }
        }
    }
    fn node_primitive(&self, node: usize) -> Option<usize> {
        match self.syntax.nodes[node].kind {
            NodeKind::Reference(variable)
                if self.syntax.variables[variable].binding == Binding::Global =>
            {
                self.catalog.bound_primitive(
                    self.syntax,
                    self.syntax.nodes[node].environment,
                    &self.syntax.variables[variable].name,
                )
            }
            _ => None,
        }
    }
    fn inline_call(&self, node: usize) -> bool {
        if !matches!(self.syntax.nodes[node].kind, NodeKind::Call) {
            return false;
        }
        let children = self.syntax.nodes[node].children.values();
        let Some(primitive) = self.node_primitive(children[0]) else {
            return false;
        };
        let specialized =
            self.catalog
                .specialize(self.syntax, self.syntax.nodes[node].environment, primitive);
        self.catalog.procedures[specialized]
            .inline_effects
            .is_some()
            && pattern_member(
                children.len() - 1,
                &self.catalog.procedures[specialized].pattern,
            )
    }
    fn trivial(&self, node: usize) -> bool {
        match self.syntax.nodes[node].kind {
            NodeKind::Constant(_) | NodeKind::Reference(_) => true,
            NodeKind::Set(_) => self.trivial(self.syntax.nodes[node].children.values()[0]),
            NodeKind::Call if self.inline_call(node) => self.syntax.nodes[node].children.values()
                [1..]
                .iter()
                .all(|&node| self.trivial(node)),
            _ => false,
        }
    }
    fn boolean_value(&self, node: usize) -> bool {
        match self.syntax.nodes[node].kind {
            NodeKind::Conjunction | NodeKind::Disjunction => self.syntax.nodes[node]
                .children
                .values()
                .iter()
                .all(|&child| self.boolean_value(child)),
            NodeKind::Call => self
                .node_primitive(self.syntax.nodes[node].children.values()[0])
                .is_some_and(|primitive| self.catalog.boolean(primitive)),
            _ => false,
        }
    }
    fn values_live(&mut self, mut live: Ids, values: &[usize]) -> Ids {
        for &value in values {
            live = live.union(&self.syntax.free_variables(value));
        }
        live
    }
    fn poll_at(&mut self, split: usize) {
        let block = self.current_block;
        let old_label = self.blocks[block].label;
        let mut first = std::mem::take(&mut self.blocks[block].instructions);
        let second = first.split_off(split);
        let last = first.back().copied().unwrap_or(old_label);
        let frame = self.instructions[last].frame.clone();
        let prefix = self.new_block(old_label);
        let next = self.new_label();
        self.blocks[prefix].instructions = first;
        let branch = self.instruction(
            InstructionKind::Jump {
                operand: label(next),
                arguments: None,
                poll: true,
            },
            frame.clone(),
            None,
        );
        self.blocks[prefix].branch = Some(branch);
        self.blocks[block].label = self.instruction(
            InstructionKind::Label {
                number: next,
                kind: LabelKind::Simple,
            },
            frame,
            None,
        );
        self.blocks[block].instructions = second;
        self.context.poll = Poll {
            since_entry: true,
            delta: 0,
        };
    }
    fn seal(&mut self, enabled: bool, where_: &str) {
        if enabled {
            while self.context.poll.delta + self.blocks[self.current_block].instructions.len() + 1
                > 90
            {
                self.poll_at(90_usize.saturating_sub(self.context.poll.delta));
            }
        }
        let delta =
            self.context.poll.delta + self.blocks[self.current_block].instructions.len() + 1;
        let poll = enabled
            && match where_ {
                "call" => delta > 75,
                "tail-call" => delta > 15,
                "return" => self.context.poll.since_entry && delta > 30,
                "internal" => false,
                _ => panic!("invalid polling transition"),
            };
        if poll {
            self.poll_at(self.blocks[self.current_block].instructions.len());
        } else {
            self.context.poll.delta = delta;
        }
    }
}

// ---- Procedure entries and argument evaluation order ----

#[derive(Clone, Copy, PartialEq, Eq)]
enum Argument {
    Node(usize),
    Return,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum Position {
    Register(usize),
    Operator,
}
#[derive(Clone, Copy)]
struct ArgumentPosition {
    argument: Argument,
    position: Position,
}
impl Generator<'_, '_> {
    fn entry_context(&self, procedure: &Procedure, closed: Ids) -> Context {
        let parameters = procedure.parameters.values();
        let stacked = parameters.len().saturating_sub(3);
        let mut slots = vec![self.specials.empty_var; stacked];
        let mut registers = vec![self.specials.empty_var; 5];
        registers[0] = self.specials.return_var;
        for (i, &variable) in parameters.iter().enumerate() {
            if i < stacked {
                slots[stacked - i - 1] = variable;
            } else {
                registers[i - stacked + 1] = variable;
            }
        }
        if !closed.empty() {
            registers[4] = self.specials.closure_var;
        }
        Context {
            size: stacked,
            slots: Ids::from_slice(&slots),
            registers: Ids::from_slice(&registers),
            closed,
            poll: Poll::entry(),
            entry_block: None,
        }
    }
    fn schedule_procedure(&mut self, node: usize, closed: Ids) -> usize {
        let first = self.new_label();
        let second = self.new_label();
        let NodeKind::Procedure(procedure) = self.syntax.nodes[node].kind.clone() else {
            unreachable!()
        };
        let mut context = self.entry_context(&procedure, closed.clone());
        let body = self.syntax.nodes[node].children.values()[0];
        let live = self
            .syntax
            .free_variables(body)
            .union(&Ids::from_slice(&[self.specials.return_var]));
        let frame = context.frame(live);
        let entry = self.instruction(
            InstructionKind::Label {
                number: first,
                kind: LabelKind::Entry {
                    parameters: procedure.parameters.values().len(),
                    minimum: procedure.minimum,
                    rest: procedure.rest,
                    closed: !closed.empty(),
                },
            },
            frame.clone(),
            Some(self.syntax.nodes[node].source),
        );
        let entry = self.new_block(entry);
        let body_label = self.instruction(
            InstructionKind::Label {
                number: second,
                kind: LabelKind::Simple,
            },
            frame.clone(),
            Some(self.syntax.nodes[node].source),
        );
        let block = self.new_block(body_label);
        context.entry_block = Some(entry);
        let jump = self.instruction(
            InstructionKind::Jump {
                operand: label(second),
                arguments: None,
                poll: false,
            },
            frame,
            None,
        );
        self.blocks[entry].branch = Some(jump);
        self.scheduled.insert(
            0,
            Box::new(ScheduledProcedure {
                node,
                block,
                context,
            }),
        );
        label(first)
    }
    fn argument_free(&mut self, argument: Argument) -> Ids {
        match argument {
            Argument::Return => Ids::default(),
            Argument::Node(node) => self.syntax.free_variables(node),
        }
    }
    fn argument_order(
        &mut self,
        operator: Option<usize>,
        arguments: &[Option<Argument>],
    ) -> Vec<ArgumentPosition> {
        let mut first = Vec::new();
        let mut second = Vec::new();
        for (i, &argument) in arguments.iter().enumerate() {
            let Some(argument) = argument else {
                continue;
            };
            let entry = ArgumentPosition {
                argument,
                position: Position::Register(i),
            };
            if matches!(argument, Argument::Return)
                || matches!(argument, Argument::Node(node) if self.trivial(node))
            {
                second.insert(0, entry);
            } else {
                first.push(entry);
            }
        }
        first.extend(self.free_variable_order(second));
        if let Some(operator) = operator {
            let entry = ArgumentPosition {
                argument: Argument::Node(operator),
                position: Position::Operator,
            };
            if self.trivial(operator) {
                first.push(entry);
            } else {
                first.insert(0, entry);
            }
        }
        first
    }
    fn free_variable_order(
        &mut self,
        mut arguments: Vec<ArgumentPosition>,
    ) -> Vec<ArgumentPosition> {
        let mut bins: Vec<(usize, usize)> = Vec::new();
        let mut result = Vec::new();
        for argument in &arguments {
            for variable in self.argument_free(argument.argument).values() {
                if let Some((_, count)) = bins.iter_mut().find(|(var, _)| *var == variable) {
                    *count += 1;
                } else {
                    bins.insert(0, (variable, 1));
                }
            }
        }
        while !arguments.is_empty() {
            let mut best = 0;
            let mut payoff = -1;
            for i in (0..arguments.len()).rev() {
                let score: i64 = self
                    .argument_free(arguments[i].argument)
                    .values()
                    .into_iter()
                    .map(|variable| {
                        let count = bins.iter().find(|(var, _)| *var == variable).unwrap().1;
                        (1000 / (count * count)) as i64
                    })
                    .sum();
                if score >= payoff {
                    best = i;
                    payoff = score;
                }
            }
            let entry = arguments.remove(best);
            for variable in self.argument_free(entry.argument).values() {
                bins.iter_mut().find(|(var, _)| *var == variable).unwrap().1 -= 1;
            }
            result.push(entry);
        }
        result
    }
    fn arguments_live(&mut self, mut live: Ids, order: &[ArgumentPosition]) -> Ids {
        for entry in order {
            live = match entry.argument {
                Argument::Return => live.adjoin(self.specials.return_var),
                Argument::Node(node) => live.union(&self.syntax.free_variables(node)),
            };
        }
        live
    }
    fn stack_arguments_live(
        &mut self,
        mut live: Ids,
        arguments: &[Option<Argument>],
        why: Why,
    ) -> Ids {
        for argument in arguments {
            match argument {
                Some(Argument::Return) if why == Why::Tail => {
                    live = live.adjoin(self.specials.return_var)
                }
                Some(Argument::Node(node)) => live = live.union(&self.syntax.free_variables(*node)),
                _ => (),
            }
        }
        live
    }
    fn all_arguments_trivial(&self, order: &[ArgumentPosition]) -> bool {
        let Some(first) = order.first() else {
            return true;
        };
        // The source short-circuits immediately on return, including its suffix.
        match first.argument {
            Argument::Return => true,
            Argument::Node(node) => self.trivial(node) && self.all_arguments_trivial(&order[1..]),
        }
    }
    fn jump_arguments(&self, nodes: &[usize]) -> (Vec<Option<Argument>>, Vec<Option<Argument>>) {
        let stacked = nodes.len().saturating_sub(3);
        let mut slots = vec![None; stacked];
        let mut registers = vec![None; 5];
        registers[0] = Some(Argument::Return);
        for (i, &node) in nodes.iter().enumerate() {
            if i < stacked {
                slots[i] = Some(Argument::Node(node));
            } else {
                registers[i - stacked + 1] = Some(Argument::Node(node));
            }
        }
        (slots, registers)
    }
    fn polling_enabled(&self, node: usize) -> bool {
        self.syntax
            .declaration(
                self.syntax.nodes[node].environment,
                "interrupts-enabled",
                None,
                atom("#t"),
            )
            .atom()
            != "#f"
    }
    fn closed_variables(&mut self, node: usize) -> Ids {
        let free = self.syntax.free_variables(node);
        let constant = self.constants.keys();
        free.difference(&constant)
    }
    fn sorted_variables(&self, variables: &Ids) -> Ids {
        let mut values = variables.values();
        values.sort_by(|a, b| {
            self.syntax.variables[*a]
                .name
                .cmp(&self.syntax.variables[*b].name)
        });
        Ids::from_slice(&values)
    }
}

// ---- Expression generation and direct continuation transitions ----

impl Generator<'_, '_> {
    fn generate_node(&mut self, node: usize, live: &Ids, why: Why) -> usize {
        let source = Some(self.syntax.nodes[node].source);
        let children = self.syntax.nodes[node].children.values();
        match self.syntax.nodes[node].kind.clone() {
            NodeKind::Constant(value) => {
                let operand = self.operands.object(Object::Literal(value));
                self.generate_return(operand, why, node)
            }
            NodeKind::Reference(variable) => {
                let operand = if why == Why::Side {
                    self.operands.object(Object::Literal(Rc::new(undefined())))
                } else if let Some(primitive) = self.node_primitive(node) {
                    self.operands.object(Object::Primitive(primitive))
                } else {
                    self.variable_operand(variable)
                        .expect("accessible reference")
                };
                self.generate_return(operand, why, node)
            }
            NodeKind::Set(variable) => {
                let operand = self.generate_node(children[0], &live.adjoin(variable), Why::Keep);
                let destination = self
                    .variable_operand(variable)
                    .expect("accessible assignment");
                self.copy(operand, destination, None, live, source);
                let undefined = self.operands.object(Object::Literal(Rc::new(undefined())));
                self.generate_return(undefined, why, node)
            }
            NodeKind::Test => self.generate_test(node, live, why),
            NodeKind::Conjunction | NodeKind::Disjunction => self.generate_boolean(node, live, why),
            NodeKind::Procedure(_) => {
                let closed = self.closed_variables(node);
                let names = self.sorted_variables(&closed);
                let entry = self.schedule_procedure(node, names.clone());
                let operand = if names.empty() {
                    self.known.add(entry % 10_000, node);
                    entry
                } else {
                    let keep = closed.union(live);
                    let top = self.highest_live_slot(&keep) % 10_000;
                    self.deallocate(self.context.size - top);
                    self.push_slot();
                    let slot = stack_slot(self.context.size);
                    let variable = self.temporary("closure");
                    self.put_variable(slot, variable);
                    let operands: Vec<_> = names
                        .values()
                        .into_iter()
                        .map(|var| self.variable_operand(var).unwrap())
                        .collect();
                    self.append(
                        InstructionKind::Close(vec![Box::new(ClosureParameters {
                            destination: slot,
                            label: entry % 10_000,
                            operands: Ids::from_slice(&operands),
                        })]),
                        live.adjoin(variable),
                        source,
                    );
                    slot
                };
                self.generate_return(operand, why, node)
            }
            NodeKind::Call if self.syntax.let_call(node) => {
                let NodeKind::Procedure(proc) = self.syntax.nodes[children[0]].kind.clone() else {
                    unreachable!()
                };
                let body = self.syntax.nodes[children[0]].children.values()[0];
                self.generate_let(&proc.parameters, &children[1..], body, live, why)
            }
            NodeKind::Call if self.inline_call(node) => {
                self.generate_inline(node, &children[1..], live, why)
            }
            NodeKind::Call => self.generate_call(node, children[0], &children[1..], live, why),
            NodeKind::Future => panic!("future GVM generation outside current checked domain"),
            NodeKind::Define(_) => panic!("definition below a program root"),
        }
    }
    fn generate_return(&mut self, operand: usize, why: Why, node: usize) -> usize {
        if why != Why::Tail {
            return operand;
        }
        let result = self.temporary("result");
        let live = Ids::from_slice(&[self.specials.return_var]);
        self.copy(
            operand,
            1,
            Some(result),
            &live,
            Some(self.syntax.nodes[node].source),
        );
        let return_operand = self
            .variable_operand(self.specials.return_var)
            .expect("return address");
        self.seal(self.polling_enabled(node), "return");
        self.deallocate(self.context.size);
        self.branch(
            InstructionKind::Jump {
                operand: return_operand,
                arguments: None,
                poll: false,
            },
            Ids::from_slice(&[result]),
            None,
        );
        1
    }
    fn generate_inline(&mut self, node: usize, args: &[usize], live: &Ids, why: Why) -> usize {
        let arguments: Vec<_> = args
            .iter()
            .map(|&node| Some(Argument::Node(node)))
            .collect();
        let order = self.argument_order(None, &arguments);
        let mut variables: Vec<_> = args.iter().map(|&node| (node, None)).collect();
        let mut current_live = live.clone();
        for i in 0..order.len() {
            let remaining: Vec<_> = order[i + 1..]
                .iter()
                .map(|entry| match entry.argument {
                    Argument::Node(node) => node,
                    Argument::Return => unreachable!(),
                })
                .collect();
            let needed = self.values_live(current_live.clone(), &remaining);
            let Argument::Node(arg) = order[i].argument else {
                unreachable!()
            };
            let operand = self.generate_node(arg, &needed, Why::Need);
            let Position::Register(position) = order[i].position else {
                unreachable!()
            };
            let temporary = self.temporary(&position.to_string());
            let variable = self.save_variable(
                operand,
                temporary,
                &needed,
                Some(self.syntax.nodes[arg].source),
            );
            variables.iter_mut().find(|(id, _)| *id == arg).unwrap().1 = Some(variable);
            current_live = current_live.adjoin(variable);
        }
        let destination = if why == Why::Side {
            0
        } else {
            self.lowest_dead_register(live)
                .unwrap_or_else(|| self.lowest_dead_slot(live))
        };
        if stack(destination) && destination % 10_000 > self.context.size {
            self.push_slot();
        }
        let operands: Vec<_> = variables
            .into_iter()
            .map(|(_, var)| self.variable_operand(var.unwrap()).unwrap())
            .collect();
        let result = self.temporary("result");
        if why != Why::Side {
            self.put_variable(destination, result);
        }
        let operator = self.syntax.nodes[node].children.values()[0];
        let primitive = self.node_primitive(operator).unwrap();
        let primitive =
            self.catalog
                .specialize(self.syntax, self.syntax.nodes[node].environment, primitive);
        self.append(
            InstructionKind::Apply {
                primitive,
                operands: Ids::from_slice(&operands),
                destination: if why == Why::Side {
                    None
                } else {
                    Some(destination)
                },
            },
            if why == Why::Side {
                live.clone()
            } else {
                live.adjoin(result)
            },
            Some(self.syntax.nodes[node].source),
        );
        self.generate_return(destination, why, node)
    }
    fn predicate(&mut self, node: usize, live: &Ids) -> (usize, usize) {
        if matches!(
            self.syntax.nodes[node].kind,
            NodeKind::Conjunction | NodeKind::Disjunction
        ) {
            return self.predicate_boolean(node, live);
        }
        if matches!(self.syntax.nodes[node].kind, NodeKind::Call) {
            let children = self.syntax.nodes[node].children.values();
            if let Some(primitive) = self.node_primitive(children[0]) {
                let specialized = self.catalog.specialize(
                    self.syntax,
                    self.syntax.nodes[node].environment,
                    primitive,
                );
                if self.catalog.procedures[specialized].test
                    && pattern_member(
                        children.len() - 1,
                        &self.catalog.procedures[specialized].pattern,
                    )
                {
                    if specialized == self.catalog.lookup("##not") {
                        let (yes, no) = self.predicate(children[1], live);
                        return (no, yes);
                    }
                    return self.predicate_test(node, live, specialized, &children[1..]);
                }
            }
        }
        let (yes, no) = self.predicate_test(node, live, self.catalog.lookup("##not"), &[node]);
        (no, yes)
    }
    fn predicate_test(
        &mut self,
        node: usize,
        live: &Ids,
        test: usize,
        args: &[usize],
    ) -> (usize, usize) {
        let mut variables = Vec::new();
        let mut current_live = live.clone();
        for i in 0..args.len() {
            let needed = self.values_live(current_live.clone(), &args[i + 1..]);
            let operand = self.generate_node(args[i], &needed, Why::Need);
            let temporary = self.temporary("predicate");
            let variable = self.save_variable(
                operand,
                temporary,
                &needed,
                Some(self.syntax.nodes[args[i]].source),
            );
            variables.push(variable);
            current_live = current_live.adjoin(variable);
        }
        let yes = self.new_label();
        let no = self.new_label();
        self.seal(self.polling_enabled(node), "internal");
        let operands: Vec<_> = variables
            .into_iter()
            .map(|var| self.variable_operand(var).unwrap())
            .collect();
        self.branch(
            InstructionKind::IfJump {
                test,
                operands: Ids::from_slice(&operands),
                true_label: yes,
                false_label: no,
                poll: false,
            },
            live.clone(),
            Some(self.syntax.nodes[node].source),
        );
        (yes, no)
    }
    fn simple_block(&mut self, number: usize, live: Ids, node: usize) -> usize {
        let label = self.instruction(
            InstructionKind::Label {
                number,
                kind: LabelKind::Simple,
            },
            self.context.frame(live),
            Some(self.syntax.nodes[node].source),
        );
        self.new_block(label)
    }
    fn predicate_boolean(&mut self, node: usize, live: &Ids) -> (usize, usize) {
        let children = self.syntax.nodes[node].children.values();
        let and = matches!(self.syntax.nodes[node].kind, NodeKind::Conjunction);
        let needed = live.union(&self.syntax.free_variables(children[1]));
        let (yes, no) = self.predicate(children[0], &needed);
        let before = self.context.clone();
        self.current_block = self.simple_block(if and { yes } else { no }, needed, children[1]);
        let (final_yes, final_no) = self.predicate(children[1], live);
        let after = self.context.clone();
        self.context = before;
        self.current_block =
            self.simple_block(if and { no } else { yes }, live.clone(), children[1]);
        self.merge_context(
            &after,
            live,
            self.polling_enabled(node),
            "internal",
            Some(self.syntax.nodes[node].source),
        );
        self.branch(
            InstructionKind::Jump {
                operand: label(if and { final_no } else { final_yes }),
                arguments: None,
                poll: false,
            },
            live.clone(),
            None,
        );
        (final_yes, final_no)
    }
    fn generate_test(&mut self, node: usize, live: &Ids, why: Why) -> usize {
        let children = self.syntax.nodes[node].children.values();
        let needed = live
            .union(&self.syntax.free_variables(children[1]))
            .union(&self.syntax.free_variables(children[2]));
        let (yes, no) = self.predicate(children[0], &needed);
        let before = self.context.clone();
        // The source's ordinary let evaluates these effectful constructors in
        // Chez's right-to-left order; labels themselves were allocated by let*.
        let alt_live = live.union(&self.syntax.free_variables(children[2]));
        let alt = self.simple_block(no, alt_live, children[2]);
        let con_live = live.union(&self.syntax.free_variables(children[1]));
        let con = self.simple_block(yes, con_live, children[1]);
        self.current_block = con;
        let value = self.generate_node(children[1], live, why);
        if why == Why::Tail {
            self.context = before;
            self.current_block = alt;
            return self.generate_node(children[2], live, why);
        }
        let result = self.temporary("result");
        let after_live = live.adjoin(result);
        self.save_to_register(
            value,
            1,
            result,
            live,
            Some(self.syntax.nodes[children[1]].source),
        );
        let con_context = self.context.clone();
        let con = self.current_block;
        self.context = before;
        self.current_block = alt;
        let value = self.generate_node(children[2], live, why);
        self.save_to_register(
            value,
            1,
            result,
            live,
            Some(self.syntax.nodes[children[2]].source),
        );
        let next = self.new_label();
        let alt = self.current_block;
        if con_context.size > self.context.size {
            self.seal(self.polling_enabled(node), "internal");
            let alt_context = self.context.clone();
            self.context = con_context;
            self.current_block = con;
            self.merge_context(
                &alt_context,
                &after_live,
                self.polling_enabled(node),
                "internal",
                Some(self.syntax.nodes[node].source),
            );
        } else {
            let alt_context = self.context.clone();
            self.context = con_context;
            self.current_block = con;
            self.seal(self.polling_enabled(node), "internal");
            let con_context = self.context.clone();
            self.context = alt_context;
            self.current_block = alt;
            self.merge_context(
                &con_context,
                &after_live,
                self.polling_enabled(node),
                "internal",
                Some(self.syntax.nodes[node].source),
            );
        }
        let frame = self.context.frame(after_live.clone());
        let first = self.instruction(
            InstructionKind::Jump {
                operand: label(next),
                arguments: None,
                poll: false,
            },
            frame.clone(),
            None,
        );
        let second = self.instruction(
            InstructionKind::Jump {
                operand: label(next),
                arguments: None,
                poll: false,
            },
            frame.clone(),
            None,
        );
        self.blocks[con].branch = Some(first);
        self.blocks[alt].branch = Some(second);
        let label = self.instruction(
            InstructionKind::Label {
                number: next,
                kind: LabelKind::Simple,
            },
            frame,
            Some(self.syntax.nodes[node].source),
        );
        self.current_block = self.new_block(label);
        1
    }
    fn generate_boolean(&mut self, node: usize, live: &Ids, why: Why) -> usize {
        let children = self.syntax.nodes[node].children.values();
        let pre = children[0];
        let alt = children[1];
        let and = matches!(self.syntax.nodes[node].kind, NodeKind::Conjunction);
        let needed = live.union(&self.syntax.free_variables(alt));
        let boolean = self.boolean_value(pre);
        let predicate = self.temporary("predicate");
        let (yes, no) = if boolean {
            self.predicate(pre, &needed)
        } else {
            let yes = self.new_label();
            let no = self.new_label();
            let operand = self.generate_node(pre, &needed, Why::Need);
            self.save_to_register(
                operand,
                1,
                predicate,
                &needed,
                Some(self.syntax.nodes[pre].source),
            );
            self.seal(self.polling_enabled(pre), "internal");
            self.branch(
                InstructionKind::IfJump {
                    test: self.catalog.lookup("##not"),
                    operands: Ids::from_slice(&[1]),
                    true_label: no,
                    false_label: yes,
                    poll: false,
                },
                needed.adjoin(predicate),
                Some(self.syntax.nodes[pre].source),
            );
            (yes, no)
        };
        let (short, alternate) = if and { (no, yes) } else { (yes, no) };
        let before = self.context.clone();
        let result = self.temporary("result");
        let con_live = if boolean {
            live.clone()
        } else {
            live.adjoin(predicate)
        };
        // These constructors are ordered by the source let*, unlike gen-tst.
        let con_block = self.simple_block(short, con_live, alt);
        let alt_live = live.union(&self.syntax.free_variables(alt));
        let alt_block = self.simple_block(alternate, alt_live, alt);
        if boolean {
            self.current_block = con_block;
            let operand = self.operands.object(Object::Literal(Rc::new(atom(if and {
                "#f"
            } else {
                "#t"
            }))));
            self.save_to_register(
                operand,
                1,
                result,
                live,
                Some(self.syntax.nodes[node].source),
            );
        } else {
            let operand = self.variable_operand(predicate).unwrap();
            self.put_variable(operand, result);
        }
        let con_context = self.context.clone();
        self.context = before;
        self.current_block = alt_block;
        let alternative = self.generate_node(alt, live, why);
        if why == Why::Tail {
            self.context = con_context;
            self.current_block = con_block;
            let return_operand = self.variable_operand(self.specials.return_var).unwrap();
            self.seal(self.polling_enabled(node), "return");
            self.deallocate(self.context.size);
            self.branch(
                InstructionKind::Jump {
                    operand: return_operand,
                    arguments: None,
                    poll: false,
                },
                Ids::from_slice(&[result]),
                None,
            );
            return 1;
        }
        let alt_context = self.context.clone();
        let alt_block = self.current_block;
        self.context = con_context;
        self.current_block = con_block;
        self.seal(self.polling_enabled(node), "internal");
        let con_context = self.context.clone();
        let next = self.new_label();
        self.context = alt_context;
        self.current_block = alt_block;
        self.save_to_register(
            alternative,
            1,
            result,
            live,
            Some(self.syntax.nodes[alt].source),
        );
        let after = live.adjoin(result);
        self.merge_context(
            &con_context,
            &after,
            self.polling_enabled(node),
            "internal",
            Some(self.syntax.nodes[node].source),
        );
        let frame = self.context.frame(after);
        for block in [alt_block, con_block] {
            let jump = self.instruction(
                InstructionKind::Jump {
                    operand: label(next),
                    arguments: None,
                    poll: false,
                },
                frame.clone(),
                None,
            );
            self.blocks[block].branch = Some(jump);
        }
        let instruction = self.instruction(
            InstructionKind::Label {
                number: next,
                kind: LabelKind::Simple,
            },
            frame,
            Some(self.syntax.nodes[node].source),
        );
        self.current_block = self.new_block(instruction);
        1
    }
    fn generate_let(
        &mut self,
        vars: &Ids,
        vals: &[usize],
        body: usize,
        live: &Ids,
        why: Why,
    ) -> usize {
        let variables = vars.values();
        let value = |var| {
            vals[variables
                .iter()
                .position(|&candidate| candidate == var)
                .unwrap()]
        };
        let procedures = Ids::from_slice(
            &variables
                .iter()
                .copied()
                .filter(|&var| matches!(self.syntax.nodes[value(var)].kind, NodeKind::Procedure(_)))
                .collect::<Vec<_>>(),
        );
        let mut constants = procedures.clone();
        loop {
            let mut keep = Vec::new();
            for var in constants.values() {
                if self
                    .closed_variables(value(var))
                    .difference(&constants)
                    .empty()
                {
                    keep.push(var);
                }
            }
            let next = Ids::from_slice(&keep);
            if next.equal_set(&constants) {
                break;
            }
            constants = next;
        }
        let mut closures = Vec::new();
        for var in procedures.values() {
            if !self
                .closed_variables(value(var))
                .difference(&constants)
                .empty()
            {
                closures.push(var);
            }
        }
        for var in constants.values() {
            let operand = self.schedule_procedure(value(var), Ids::default());
            self.known.add(operand % 10_000, value(var));
            self.constants.add(var, operand);
        }
        let ordinary: Vec<_> = variables
            .iter()
            .copied()
            .filter(|var| !constants.has(*var) && !closures.contains(var))
            .collect();
        let mut captured = Ids::default();
        // apply set-union retains source operand order rather than reversing it.
        for &var in closures.iter().rev() {
            captured = self
                .closed_variables(value(var))
                .difference(&constants)
                .union(&captured);
        }
        let liv = live
            .union(&captured)
            .union(&self.syntax.free_variables(body));
        for (i, &var) in ordinary.iter().enumerate() {
            let remaining: Vec<_> = ordinary[i + 1..].iter().map(|&var| value(var)).collect();
            let needed = self.values_live(liv.clone(), &remaining);
            let useless = self.syntax.variables[var].references.empty()
                && self.syntax.variables[var].assignments.empty();
            let operand = self.generate_node(
                value(var),
                &needed,
                if useless { Why::Side } else { Why::Need },
            );
            if !useless {
                self.save_value(
                    operand,
                    var,
                    &needed,
                    Some(self.syntax.nodes[value(var)].source),
                );
            }
        }
        if !closures.is_empty() {
            let top = self.highest_live_slot(&liv) % 10_000;
            self.deallocate(self.context.size - top);
            for &var in &closures {
                self.push_slot();
                self.put_variable(stack_slot(self.context.size), var);
            }
            let mut parameters = Vec::new();
            for var in closures {
                let closed = self.closed_variables(value(var)).difference(&constants);
                let closed = self.sorted_variables(&closed);
                assert!(!closed.empty());
                let entry = self.schedule_procedure(value(var), closed.clone());
                let operands: Vec<_> = closed
                    .values()
                    .into_iter()
                    .map(|var| self.variable_operand(var).unwrap())
                    .collect();
                parameters.push(Box::new(ClosureParameters {
                    destination: self.variable_operand(var).unwrap(),
                    label: entry % 10_000,
                    operands: Ids::from_slice(&operands),
                }));
            }
            self.append(
                InstructionKind::Close(parameters),
                liv,
                Some(self.syntax.nodes[body].source),
            );
        }
        self.generate_node(body, live, why)
    }
    fn call_argument(
        &mut self,
        arg: Argument,
        return_label: Option<usize>,
        live: &Ids,
        why: Why,
    ) -> usize {
        match arg {
            Argument::Return if why == Why::Tail => {
                self.variable_operand(self.specials.return_var).unwrap()
            }
            Argument::Return => label(return_label.unwrap()),
            Argument::Node(node) => self.generate_node(node, live, Why::Need),
        }
    }
    fn generate_call(
        &mut self,
        node: usize,
        operator: usize,
        args: &[usize],
        live: &Ids,
        why: Why,
    ) -> usize {
        let local = match self.syntax.nodes[operator].kind {
            NodeKind::Reference(var) => {
                let operand = self.variable_operand(var).unwrap();
                if operand / 10_000 != 2 {
                    None
                } else {
                    self.known.get(operand % 10_000).and_then(|pair| {
                        let NodeKind::Procedure(proc) = &self.syntax.nodes[pair.value.get()].kind
                        else {
                            unreachable!()
                        };
                        (!proc.rest
                            && proc.minimum == args.len()
                            && proc.parameters.values().len() == args.len())
                        .then_some(operand % 10_000)
                    })
                }
            }
            _ => None,
        };
        let (stack_args, reg_args) = self.jump_arguments(args);
        let order = self.argument_order(
            if local.is_some() {
                None
            } else {
                Some(operator)
            },
            &reg_args,
        );
        let after = if why == Why::Tail {
            live.remove(self.specials.return_var)
        } else {
            live.clone()
        };
        let for_regs = self.arguments_live(live.clone(), &order);
        let return_label = if why == Why::Tail {
            None
        } else {
            Some(self.new_label())
        };
        let save_live = self.stack_arguments_live(for_regs.clone(), &stack_args, why);
        let registers = self.live_registers(&after);
        self.save_registers(&registers, &save_live, Some(self.syntax.nodes[node].source));
        let frame_start = self.highest_live_slot(&after) % 10_000;
        let mut liv = after;
        for (i, &arg) in stack_args.iter().enumerate() {
            let destination = stack_slot(frame_start + i + 1);
            let needed = self
                .stack_arguments_live(liv.clone(), &stack_args[i + 1..], why)
                .union(&for_regs);
            if let Some(arg) = arg {
                let var = if matches!(arg, Argument::Return) && why == Why::Tail {
                    self.specials.return_var
                } else {
                    self.temporary(&format!("-{}", i + 1))
                };
                let operand = self.call_argument(arg, return_label, &needed, why);
                let source = match arg {
                    Argument::Node(arg) => arg,
                    Argument::Return => node,
                };
                self.save_to_slot(
                    operand,
                    destination,
                    var,
                    &needed,
                    Some(self.syntax.nodes[source].source),
                );
                liv = liv.adjoin(var);
            } else if destination % 10_000 > self.context.size {
                let operand = self.operands.object(Object::Literal(Rc::new(undefined())));
                self.copy(
                    operand,
                    destination,
                    Some(self.specials.empty_var),
                    &liv,
                    Some(self.syntax.nodes[node].source),
                );
            }
        }
        let mut reg_map = Vec::new();
        let mut operator_var = None;
        for (i, entry) in order.iter().enumerate() {
            let needed = self.arguments_live(liv.clone(), &order[i + 1..]);
            let var = if matches!(entry.argument, Argument::Return) && why == Why::Tail {
                self.specials.return_var
            } else {
                self.temporary(match entry.position {
                    Position::Operator => "operator",
                    Position::Register(_) => "argument",
                })
            };
            let operand = self.call_argument(entry.argument, return_label, &needed, why);
            let source = match entry.argument {
                Argument::Node(arg) => arg,
                Argument::Return => node,
            };
            if matches!(entry.position, Position::Operator) {
                if let Argument::Node(arg) = entry.argument {
                    if let NodeKind::Reference(var) = self.syntax.nodes[arg].kind {
                        if !matches!(operand / 10_000, 2 | 5) {
                            liv = liv.adjoin(var);
                            operator_var = Some(var);
                            continue;
                        }
                    }
                }
                self.save_argument(
                    operand,
                    var,
                    &needed,
                    Some(self.syntax.nodes[source].source),
                );
                operator_var = Some(var);
            } else {
                let Position::Register(reg) = entry.position else {
                    unreachable!()
                };
                if self.all_arguments_trivial(&order[i + 1..]) {
                    self.save_to_register(
                        operand,
                        reg,
                        var,
                        &needed,
                        Some(self.syntax.nodes[source].source),
                    );
                } else {
                    self.save_in_slot(
                        operand,
                        var,
                        &needed,
                        Some(self.syntax.nodes[source].source),
                    );
                }
                reg_map.insert(0, (reg, var));
            }
            liv = liv.adjoin(var);
        }
        for i in (0..5).rev() {
            if let Some(&(_, var)) = reg_map.iter().find(|(reg, _)| *reg == i) {
                if ids_nth(&self.context.registers, i) != Some(var) {
                    let operand = self.variable_operand(var).unwrap();
                    self.save_to_register(
                        operand,
                        i,
                        var,
                        &liv,
                        Some(self.syntax.nodes[node].source),
                    );
                }
            }
        }
        let operand = local
            .map(|entry| label(entry + 1))
            .unwrap_or_else(|| self.variable_operand(operator_var.unwrap()).unwrap());
        self.seal(
            self.polling_enabled(node),
            if return_label.is_some() {
                "call"
            } else {
                "tail-call"
            },
        );
        self.deallocate(self.context.size - frame_start - stack_args.len());
        self.branch(
            InstructionKind::Jump {
                operand,
                arguments: if local.is_some() {
                    None
                } else {
                    Some(args.len())
                },
                poll: false,
            },
            liv,
            Some(self.syntax.nodes[node].source),
        );
        let result = self.temporary("result");
        self.deallocate(self.context.size - frame_start);
        self.context.registers = Ids::default();
        self.put_variable(1, result);
        if let Some(number) = return_label {
            self.context.poll = self.context.poll.returned();
            let instruction = self.instruction(
                InstructionKind::Label {
                    number,
                    kind: LabelKind::Return,
                },
                self.context.frame(live.adjoin(result)),
                Some(self.syntax.nodes[node].source),
            );
            self.current_block = self.new_block(instruction);
        }
        1
    }
    fn merge_context(
        &mut self,
        other: &Context,
        live: &Ids,
        enabled: bool,
        where_: &str,
        source: Option<usize>,
    ) {
        let live = self.live_variables(live);
        for i in (0..5).rev() {
            let desired = ids_nth(&other.registers, i);
            let current = ids_nth(&self.context.registers, i);
            if desired != current && desired.is_some_and(|var| live.has(var)) {
                self.put_variable(i, self.specials.empty_var);
                if let Some(current) = current {
                    if live.has(current)
                        && !self.context.registers.has(current)
                        && !self.context.slots.has(current)
                    {
                        self.copy(
                            i,
                            stack_slot(self.context.size + 1),
                            Some(current),
                            &live,
                            source,
                        );
                    }
                }
                let desired = desired.unwrap();
                let operand = self.variable_operand(desired).unwrap();
                self.copy(operand, i, Some(desired), &live, source);
            }
        }
        for i in 1..=other.size {
            let desired = ids_nth(&other.slots, other.size - i);
            let current = if i <= self.context.size {
                ids_nth(&self.context.slots, self.context.size - i)
            } else {
                None
            };
            if desired != current && desired.is_some_and(|var| live.has(var)) {
                let slot = stack_slot(i);
                if i <= self.context.size {
                    self.put_variable(slot, self.specials.empty_var);
                }
                if let Some(current) = current {
                    if live.has(current)
                        && !self.context.registers.has(current)
                        && !self.context.slots.has(current)
                    {
                        self.copy(
                            slot,
                            stack_slot(self.context.size + 1),
                            Some(current),
                            &live,
                            source,
                        );
                    }
                }
                let desired = desired.unwrap();
                let operand = self.variable_operand(desired).unwrap();
                self.copy(operand, slot, Some(desired), &live, source);
            } else if i > self.context.size {
                let undefined = self.operands.object(Object::Literal(Rc::new(undefined())));
                self.copy(
                    undefined,
                    stack_slot(self.context.size + 1),
                    Some(self.specials.empty_var),
                    &live,
                    source,
                );
            }
        }
        self.deallocate(self.context.size - other.size);
        for i in (0..5).rev() {
            if ids_nth(&other.registers, i) != ids_nth(&self.context.registers, i) {
                self.put_variable(i, self.specials.empty_var);
            }
        }
        for i in 1..=other.size {
            if ids_nth(&other.slots, other.size - i)
                != ids_nth(&self.context.slots, self.context.size - i)
            {
                self.put_variable(stack_slot(i), self.specials.empty_var);
            }
        }
        self.seal(enabled, where_);
        self.context.poll = self.context.poll.merge(other.poll);
        assert_eq!(self.context.entry_block, other.entry_block);
    }
}

// ---- Top-level definitions and procedure work queue ----

impl Generator<'_, '_> {
    fn procedure_object(
        &mut self,
        name: String,
        primitive: bool,
        blocks: Option<usize>,
        pattern: Datum,
    ) -> usize {
        let id = self.procedures.len();
        self.procedures.push(Box::new(CompiledProcedure {
            name,
            primitive,
            blocks,
            pattern,
        }));
        self.operands.object(Object::Procedure(id))
    }
    fn drain_procedures(&mut self) {
        while !self.scheduled.is_empty() {
            let scheduled = self.scheduled.remove(0);
            self.current_block = scheduled.block;
            self.context = scheduled.context;
            let body = self.syntax.nodes[scheduled.node].children.values()[0];
            self.generate_node(
                body,
                &Ids::from_slice(&[self.specials.return_var]),
                Why::Tail,
            );
        }
    }
    fn generate_program(&mut self, nodes: &[usize]) -> usize {
        self.current_group = self.new_group();
        let first = self.new_label();
        let second = self.new_label();
        self.groups[self.current_group].entry = first;
        let live = Ids::from_slice(&[self.specials.return_var]);
        let frame = self.context.frame(live.clone());
        let source = nodes.first().map(|&node| self.syntax.nodes[node].source);
        let entry = self.instruction(
            InstructionKind::Label {
                number: first,
                kind: LabelKind::Entry {
                    parameters: 0,
                    minimum: 0,
                    rest: false,
                    closed: false,
                },
            },
            frame.clone(),
            source,
        );
        let entry = self.new_block(entry);
        self.context.entry_block = Some(entry);
        let jump = self.instruction(
            InstructionKind::Jump {
                operand: label(second),
                arguments: None,
                poll: false,
            },
            frame.clone(),
            None,
        );
        self.blocks[entry].branch = Some(jump);
        let body = self.instruction(
            InstructionKind::Label {
                number: second,
                kind: LabelKind::Simple,
            },
            frame,
            source,
        );
        self.current_block = self.new_block(body);
        for &node in nodes {
            let NodeKind::Define(var) = self.syntax.nodes[node].kind else {
                continue;
            };
            if let Some(value) = self.syntax.global_value(var) {
                if let NodeKind::Procedure(procedure) = self.syntax.nodes[value].kind.clone() {
                    let operand = self.procedure_object(
                        self.syntax.variables[var].name.clone(),
                        true,
                        None,
                        procedure_pattern(&procedure),
                    );
                    self.constants.add(var, operand);
                }
            }
        }
        for (i, &node) in nodes.iter().enumerate() {
            if let NodeKind::Define(var) = self.syntax.nodes[node].kind {
                let value = self.syntax.nodes[node].children.values()[0];
                self.generate_definition(var, value);
            } else if i + 1 == nodes.len() {
                self.generate_node(node, &live, Why::Tail);
                break;
            } else {
                self.generate_node(node, &live, Why::Need);
            }
        }
        if nodes
            .last()
            .is_none_or(|&node| matches!(self.syntax.nodes[node].kind, NodeKind::Define(_)))
        {
            let operand = self.variable_operand(self.specials.return_var).unwrap();
            self.seal(true, "return");
            self.deallocate(self.context.size);
            self.branch(
                InstructionKind::Jump {
                    operand,
                    arguments: None,
                    poll: false,
                },
                Ids::default(),
                None,
            );
        }
        self.drain_procedures();
        if self.purify_blocks {
            self.purify();
        }
        self.procedure_object(
            "#!program".to_owned(),
            true,
            Some(self.current_group),
            Datum::List(vec![atom("0")]),
        )
    }
    fn generate_definition(&mut self, var: usize, node: usize) {
        let live = Ids::from_slice(&[self.specials.return_var]);
        let source = Some(self.syntax.nodes[node].source);
        let NodeKind::Procedure(procedure) = self.syntax.nodes[node].kind.clone() else {
            // Chez evaluates put-copy's destination before its effectful source.
            let destination = self.operands.global(&self.syntax.variables[var].name);
            let operand = self.generate_node(node, &live, Why::Need);
            self.copy(operand, destination, None, &live, source);
            return;
        };
        let previous_group = self.current_group;
        let previous_block = self.current_block;
        let previous_context = self.context.clone();
        let previous_scheduled = std::mem::take(&mut self.scheduled);
        let previous_known = std::mem::take(&mut self.known);
        self.current_group = self.new_group();
        let group = self.current_group;
        let entry = self.schedule_procedure(node, Ids::default());
        self.groups[group].entry = entry % 10_000;
        let constant = self.constants.get(var);
        let previous_operand = constant.as_ref().map(|pair| pair.value.get());
        if let Some(pair) = &constant {
            pair.value.set(entry);
            self.known.add(entry % 10_000, node);
        }
        self.drain_procedures();
        if self.purify_blocks {
            self.purify();
        }
        if let Some(pair) = constant {
            pair.value.set(previous_operand.unwrap());
        }
        self.current_group = previous_group;
        self.current_block = previous_block;
        self.context = previous_context;
        self.scheduled = previous_scheduled;
        self.known = previous_known;
        let operand = if let Some(operand) = previous_operand {
            let OperandEntry::Object(Object::Procedure(id)) = self.operands.entry(operand) else {
                unreachable!()
            };
            self.procedures[*id].blocks = Some(group);
            operand
        } else {
            self.procedure_object(
                self.syntax.variables[var].name.clone(),
                false,
                Some(group),
                procedure_pattern(&procedure),
            )
        };
        let destination = self.operands.global(&self.syntax.variables[var].name);
        self.copy(operand, destination, None, &live, source);
    }
}

fn procedure_pattern(procedure: &Procedure) -> Datum {
    let n = procedure.parameters.values().len();
    let prefix: Vec<_> = (procedure.minimum..if procedure.rest { n - 1 } else { n + 1 })
        .map(|i| atom(&i.to_string()))
        .collect();
    if !procedure.rest {
        Datum::List(prefix)
    } else if prefix.is_empty() {
        atom(&(n - 1).to_string())
    } else {
        Datum::Dotted(prefix, Box::new(atom(&(n - 1).to_string())))
    }
}

// ---- Complete intermediate diagnostics outside benchmark timers ----

struct Snapshot {
    variables: Vec<usize>,
    procedures: Vec<usize>,
    pending: VecDeque<usize>,
    slot_audit: bool,
}
impl Snapshot {
    fn new(slot_audit: bool) -> Self {
        Self {
            variables: vec![],
            procedures: vec![],
            pending: VecDeque::new(),
            slot_audit,
        }
    }
    fn variable(&mut self, generator: &Generator<'_, '_>, var: usize) -> Datum {
        if var == generator.specials.return_var {
            return atom("return");
        }
        if var == generator.specials.closure_var {
            return atom("closure");
        }
        if var == generator.specials.empty_var {
            return atom("empty");
        }
        if generator.syntax.variables[var].binding == Binding::Global {
            return Datum::List(vec![
                atom("global"),
                atom(&generator.syntax.variables[var].name),
            ]);
        }
        let id = self
            .variables
            .iter()
            .position(|&other| other == var)
            .unwrap_or_else(|| {
                self.variables.push(var);
                self.variables.len() - 1
            });
        atom(&id.to_string())
    }
    fn variables(&mut self, generator: &Generator<'_, '_>, vars: &Ids) -> Datum {
        Datum::List(
            vars.values()
                .into_iter()
                .map(|var| self.variable(generator, var))
                .collect(),
        )
    }
    fn frame(&mut self, generator: &Generator<'_, '_>, frame: &Frame) -> Datum {
        Datum::List(vec![
            atom(&frame.size.to_string()),
            self.variables(generator, &frame.slots),
            self.variables(generator, &frame.registers),
            self.variables(generator, &frame.closed),
            self.variables(generator, &frame.live),
        ])
    }
    fn operand(&mut self, generator: &Generator<'_, '_>, operand: usize) -> Datum {
        let semantic = match operand / 10_000 {
            0 => Datum::List(vec![atom("register"), atom(&operand.to_string())]),
            1 => Datum::List(vec![atom("stack"), atom(&(operand % 10_000).to_string())]),
            2 => Datum::List(vec![atom("label"), atom(&(operand % 10_000).to_string())]),
            _ => match generator.operands.entry(operand) {
                OperandEntry::Global(name) => Datum::List(vec![atom("global"), atom(name)]),
                OperandEntry::Closure { base, index } => Datum::List(vec![
                    atom("closure"),
                    self.operand(generator, *base),
                    atom(&index.to_string()),
                ]),
                OperandEntry::Object(Object::Literal(value)) => {
                    Datum::List(vec![atom("object"), (**value).clone()])
                }
                OperandEntry::Object(Object::Primitive(id)) => Datum::List(vec![
                    atom("primitive"),
                    atom(&generator.catalog.procedures[*id].key),
                ]),
                OperandEntry::Object(Object::Procedure(id)) => {
                    let index = self
                        .procedures
                        .iter()
                        .position(|other| other == id)
                        .unwrap_or_else(|| {
                            self.procedures.push(*id);
                            self.pending.push_back(*id);
                            self.procedures.len() - 1
                        });
                    Datum::List(vec![atom("procedure"), atom(&index.to_string())])
                }
            },
        };
        Datum::List(vec![atom(&operand.to_string()), semantic])
    }
    fn operands(&mut self, generator: &Generator<'_, '_>, operands: &Ids) -> Datum {
        Datum::List(
            operands
                .values()
                .into_iter()
                .map(|operand| self.operand(generator, operand))
                .collect(),
        )
    }
    fn instruction(&mut self, generator: &Generator<'_, '_>, instruction: usize) -> Datum {
        let instruction = &generator.instructions[instruction];
        let mut fields = match &instruction.kind {
            InstructionKind::Label { number, kind } => {
                let kind = match kind {
                    LabelKind::Simple => vec![atom("simple")],
                    LabelKind::Entry {
                        parameters,
                        minimum,
                        rest,
                        closed,
                    } => vec![
                        atom("entry"),
                        atom(&parameters.to_string()),
                        atom(&minimum.to_string()),
                        atom(if *rest { "#t" } else { "#f" }),
                        atom(if *closed { "#t" } else { "#f" }),
                    ],
                    LabelKind::Return => vec![atom("return")],
                    LabelKind::TaskEntry => vec![atom("task-entry")],
                    LabelKind::TaskReturn => vec![atom("task-return")],
                };
                vec![atom("label"), atom(&number.to_string()), Datum::List(kind)]
            }
            InstructionKind::Apply {
                primitive,
                operands,
                destination,
            } => vec![
                atom("apply"),
                atom(&generator.catalog.procedures[*primitive].key),
                self.operands(generator, operands),
                destination
                    .map(|operand| self.operand(generator, operand))
                    .unwrap_or_else(|| atom("#f")),
            ],
            InstructionKind::Copy {
                operand,
                destination,
            } => vec![
                atom("copy"),
                self.operand(generator, *operand),
                self.operand(generator, *destination),
            ],
            InstructionKind::Close(parameters) => vec![
                atom("close"),
                Datum::List(
                    parameters
                        .iter()
                        .map(|parms| {
                            Datum::List(vec![
                                self.operand(generator, parms.destination),
                                atom(&parms.label.to_string()),
                                self.operands(generator, &parms.operands),
                            ])
                        })
                        .collect(),
                ),
            ],
            InstructionKind::IfJump {
                test,
                operands,
                true_label,
                false_label,
                poll,
            } => vec![
                atom("ifjump"),
                atom(&generator.catalog.procedures[*test].key),
                self.operands(generator, operands),
                atom(&true_label.to_string()),
                atom(&false_label.to_string()),
                atom(if *poll { "#t" } else { "#f" }),
            ],
            InstructionKind::Jump {
                operand,
                arguments,
                poll,
            } => vec![
                atom("jump"),
                self.operand(generator, *operand),
                arguments
                    .map(|n| atom(&n.to_string()))
                    .unwrap_or_else(|| atom("#f")),
                atom(if *poll { "#t" } else { "#f" }),
            ],
        };
        fields.push(self.frame(generator, &instruction.frame));
        Datum::List(fields)
    }
    fn graph(&mut self, generator: &Generator<'_, '_>, operand: usize) -> Datum {
        self.operand(generator, operand);
        let mut result = Vec::new();
        while let Some(id) = self.pending.pop_front() {
            let procedure = &generator.procedures[id];
            let code = procedure
                .blocks
                .map(|group| {
                    Datum::List(
                        generator.groups[group]
                            .blocks
                            .iter()
                            .map(|&block| {
                                let block = &generator.blocks[block];
                                let mut code = vec![self.instruction(generator, block.label)];
                                for &instruction in &block.instructions {
                                    code.push(self.instruction(generator, instruction));
                                }
                                code.push(self.instruction(generator, block.branch.unwrap()));
                                Datum::List(code)
                            })
                            .collect(),
                    )
                })
                .unwrap_or_else(|| atom("#f"));
            let mut fields = vec![
                Datum::String(procedure.name.clone()),
                atom(if procedure.primitive { "#t" } else { "#f" }),
                procedure.pattern.clone(),
                code,
            ];
            if self.slot_audit {
                let slots = procedure
                    .blocks
                    .map(|group| {
                        Datum::List(
                            generator
                                .code_list(group)
                                .iter()
                                .map(|code| atom(&code.slots_needed.to_string()))
                                .collect(),
                        )
                    })
                    .unwrap_or_else(|| atom("#f"));
                fields.push(slots);
            }
            result.push(Datum::List(fields));
        }
        Datum::List(result)
    }
}

pub(super) fn intermediate(syntax: &mut Compiler<'_>, nodes: &[usize], purify: bool) -> Datum {
    let catalog = Catalog::new();
    let specials = Specials {
        return_var: syntax.variable(usize::MAX, "ret", Binding::Temporary),
        closure_var: syntax.variable(usize::MAX, "closure-env", Binding::Temporary),
        empty_var: syntax.variable(usize::MAX, "empty", Binding::Temporary),
    };
    let mut generator = Generator::new(syntax, &catalog, OperandTable::new(), specials);
    generator.purify_blocks = purify;
    let operand = generator.generate_program(nodes);
    Snapshot::new(purify).graph(&generator, operand)
}

pub(super) fn assembly(
    syntax: &mut Compiler<'_>,
    nodes: &[usize],
    catalog: &Catalog,
    operands: OperandTable,
    word_audit: bool,
) -> (Vec<String>, Option<Vec<u16>>) {
    let specials = Specials {
        return_var: syntax.variable(usize::MAX, "ret", Binding::Temporary),
        closure_var: syntax.variable(usize::MAX, "closure-env", Binding::Temporary),
        empty_var: syntax.variable(usize::MAX, "empty", Binding::Temporary),
    };
    let mut generator = Generator::new(syntax, catalog, operands, specials);
    generator.purify_blocks = true;
    let operand = generator.generate_program(nodes);
    let OperandEntry::Object(root) = generator.operands.entry(operand) else {
        unreachable!()
    };
    let output = asm::program(&generator, root.clone(), word_audit);
    (output.lines, output.word_audit)
}

// ---- Persistent location-list operations ----

fn ids_suffix(ids: &Ids, count: usize) -> Ids {
    if count == 0 {
        return ids.clone();
    }
    ids_suffix(&ids.0.as_ref().expect("list suffix").next, count - 1)
}
fn ids_nth(ids: &Ids, index: usize) -> Option<usize> {
    let cell = ids.0.as_ref()?;
    if index == 0 {
        Some(cell.id)
    } else {
        ids_nth(&cell.next, index - 1)
    }
}
fn ids_position(ids: &Ids, value: usize) -> Option<usize> {
    let cell = ids.0.as_ref()?;
    if cell.id == value {
        Some(0)
    } else {
        ids_position(&cell.next, value).map(|index| index + 1)
    }
}
fn ids_replace(ids: &Ids, index: usize, value: usize, empty: usize) -> Ids {
    match &ids.0 {
        None if index == 0 => Ids::cons(value, Ids::default()),
        None => Ids::cons(empty, ids_replace(ids, index - 1, value, empty)),
        Some(cell) if index == 0 => Ids::cons(value, cell.next.clone()),
        Some(cell) => Ids::cons(cell.id, ids_replace(&cell.next, index - 1, value, empty)),
    }
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn temporary_binding_replacement_keeps_the_shared_pair_across_new_prefixes() {
        let mut bindings = Bindings::default();
        bindings.add(1, 20);
        let saved = bindings.clone();
        let pair = bindings.get(1).unwrap();
        let previous = pair.value.replace(99);
        bindings.add(2, 21);
        assert_eq!(saved.get(1).unwrap().value.get(), 99);
        assert!(Rc::ptr_eq(&pair, &bindings.get(1).unwrap()));
        pair.value.set(previous);
        assert_eq!(bindings.get(1).unwrap().value.get(), 20);
    }
    #[test]
    fn target_catalog_preserves_all_original_descriptions_and_shared_specializations() {
        let catalog = Catalog::new();
        assert_eq!(catalog.procedures.len(), 360);
        assert_eq!(catalog.common.len(), 178);
        assert_eq!(catalog.r4rs.len(), 17);
        assert_eq!(catalog.multilisp.len(), 2);
        let syntax = Compiler::new();
        let mut syntax = syntax;
        let env = syntax.frame(None, Ids::default());
        let not = catalog.lookup("not");
        let internal_not = catalog.lookup("##not");
        assert_eq!(catalog.specialize(&syntax, env, not), internal_not);
        let env = syntax.declare(
            env,
            Declaration {
                kind: "arith".into(),
                value: atom("fixnum"),
                names: vec![],
                next: None,
            },
        );
        assert_eq!(
            catalog.specialize(&syntax, env, catalog.lookup("+")),
            catalog.lookup("##fixnum.+")
        );
    }
    #[test]
    fn replacement_preserves_suffix_sharing_and_extends_only_with_empty_variables() {
        let original = Ids::from_slice(&[1, 2, 3]);
        let replaced = ids_replace(&original, 1, 4, 0);
        assert_eq!(replaced.values(), vec![1, 4, 3]);
        assert!(Rc::ptr_eq(
            replaced
                .0
                .as_ref()
                .unwrap()
                .next
                .0
                .as_ref()
                .unwrap()
                .next
                .0
                .as_ref()
                .unwrap(),
            original
                .0
                .as_ref()
                .unwrap()
                .next
                .0
                .as_ref()
                .unwrap()
                .next
                .0
                .as_ref()
                .unwrap()
        ));
        assert_eq!(
            ids_replace(&Ids::default(), 2, 4, 0).values(),
            vec![0, 0, 4]
        );
    }
}
