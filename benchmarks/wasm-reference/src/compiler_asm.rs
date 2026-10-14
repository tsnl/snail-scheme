use super::*;
use std::cell::Cell;

#[path = "compiler_68000.rs"]
mod m68000;

pub(super) fn program(generator: &Generator<'_, '_>, root: Object, word_audit: bool) -> ObjectFile {
    m68000::program(generator, root, word_audit)
}

// ---- Object-file words, symbols and assembly lines ----

const BITS_FALSE: i64 = -33_686_019 * 8 + 7;
const BITS_NULL: i64 = -67_372_037 * 8 + 7;
const BITS_TRUE: i64 = -2 * 8 + 7;
const BITS_UNDEFINED: i64 = -3 * 8 + 7;

fn upper_word(value: i64) -> i64 {
    // Keep the source's R7RS div-based negative formula, including its quirk.
    if value >= 0 {
        value.div_euclid(65_536)
    } else if value >= -65_536 {
        -1
    } else {
        (value + 65_537).div_euclid(65_536) - 2
    }
}
fn object_encoding(object: &Object) -> Option<i64> {
    let Object::Literal(value) = object else {
        return None;
    };
    match &**value {
        Datum::Atom(text) if text == "#f" => Some(BITS_FALSE),
        Datum::Atom(text) if text == "#t" => Some(BITS_TRUE),
        Datum::Atom(text) if text == "#[undefined]" => Some(BITS_UNDEFINED),
        Datum::Atom(text) => text
            .parse::<i64>()
            .ok()
            .filter(|&n| (-268_435_456..=268_435_455).contains(&n))
            .map(|n| n * 8),
        Datum::List(values) if values.is_empty() => Some(BITS_NULL),
        Datum::Character(character) => Some(*character as i64 * 8 + 7),
        _ => None,
    }
}

pub(super) struct ObjectFile {
    pub(super) lines: Vec<String>,
    symbols: Vec<String>,
    pub(super) word_audit: Option<Vec<u16>>,
}
pub(super) enum Fragment {
    Literal(&'static str),
    Text(String),
    Number(i64),
}
impl ObjectFile {
    pub(super) fn new(audit: bool) -> Self {
        Self {
            lines: vec![],
            symbols: vec![],
            word_audit: audit.then(Vec::new),
        }
    }
    fn word(&mut self, value: i64) {
        // Original binary writes are disabled, but word normalization and all
        // assembler processing remain. This explicit opacity retains that work.
        let word = std::hint::black_box(value.rem_euclid(65_536) as u16);
        if let Some(words) = &mut self.word_audit {
            words.push(word);
        }
    }
    pub(super) fn long(&mut self, value: i64) {
        self.word(upper_word(value));
        self.word(value);
    }
    pub(super) fn line(&mut self, value: String) {
        self.lines.push(value);
    }
    fn fragments(&mut self, fragments: &[Fragment]) {
        let mut line = String::new();
        for fragment in fragments {
            match fragment {
                Fragment::Literal(text) => line.push_str(text),
                Fragment::Text(text) => line.push_str(text),
                Fragment::Number(number) => line.push_str(&number.to_string()),
            }
        }
        self.line(line);
    }
    fn string_words(&mut self, text: &str) {
        let characters: Vec<_> = text.chars().collect();
        for pair in characters.chunks(2) {
            self.word(pair[0] as i64 * 256 + pair.get(1).copied().map(|c| c as i64).unwrap_or(0));
        }
        if characters.len() % 2 == 0 {
            self.word(0);
        }
    }
    fn symbol_word(&mut self, tag: i64, name: &str) {
        if let Some(index) = self.symbols.iter().position(|other| other == name) {
            self.word(tag + index as i64);
        } else {
            self.symbols.push(name.to_owned());
            self.word(tag + 2047);
            self.string_words(name);
        }
    }
    fn symbol_long(&mut self, tag: i64, name: &str) {
        if let Some(index) = self.symbols.iter().position(|other| other == name) {
            self.long(tag + index as i64 * 8);
        } else {
            self.symbols.push(name.to_owned());
            self.long(tag + 16_383 * 8);
            self.string_words(name);
        }
    }
    fn reference(
        &mut self,
        object: &Object,
        generator: &Generator<'_, '_>,
        objects: &mut ObjectQueue,
    ) {
        if let Some(value) = object_encoding(object) {
            self.long(value);
            return;
        }
        if let Object::Literal(value) = object {
            if let Some(name) = symbol(value) {
                self.symbol_long(-393_209, name);
                return;
            }
        }
        if let Some(index) = objects.add(object.clone(), generator) {
            self.long(-524_281 + index as i64 * 8);
        } else {
            let name = match object {
                Object::Primitive(id) => &generator.catalog.procedures[*id].name,
                Object::Procedure(id) => &generator.procedures[*id].name,
                _ => unreachable!(),
            };
            self.symbol_long(-262_137, name);
        }
    }
}

pub(super) struct ObjectQueue {
    pub(super) seen: Vec<Object>,
    pub(super) pending: VecDeque<Object>,
}
impl ObjectQueue {
    pub(super) fn new() -> Self {
        Self {
            seen: vec![],
            pending: VecDeque::new(),
        }
    }
    pub(super) fn add(&mut self, object: Object, generator: &Generator<'_, '_>) -> Option<usize> {
        if matches!(object, Object::Primitive(_)) {
            return None;
        }
        if let Object::Procedure(id) = object {
            generator.procedures[id].blocks?;
        }
        if let Some(index) = self
            .seen
            .iter()
            .position(|other| object_eqv(other, &object))
        {
            return Some(index);
        }
        let index = self.seen.len();
        self.seen.push(object.clone());
        self.pending.push_back(object);
        Some(index)
    }
}

// ---- Mutable label locations shared by resolved relocation records ----

struct Label {
    number: usize,
    location: Cell<i64>,
    descriptor_position: Option<Rc<Cell<i64>>>,
}
#[derive(Clone)]
enum Target {
    Number(usize),
    Label(Rc<Label>),
}
impl Target {
    fn location(&self) -> i64 {
        match self {
            Self::Label(label) => label.location.get(),
            Self::Number(_) => panic!("unresolved assembly label"),
        }
    }
}
enum Part {
    Word(u16),
    Label(Rc<Label>),
    Align {
        boundary: i64,
        offset: i64,
    },
    Branch {
        opcode: i64,
        target: Target,
        wide: bool,
    },
    WordRelative {
        target: Target,
        offset: i64,
    },
    LongRelative {
        target: Target,
        offset: i64,
        low: i64,
    },
    Text(Vec<Fragment>),
    GvmComment(usize),
    GlobalReference(usize),
    GlobalAssignment(usize),
    GlobalJump(usize),
    ProcedureReference {
        index: usize,
        offset: i64,
    },
    PrimitiveReference {
        object: Object,
        offset: i64,
    },
    M68020,
    M68881,
}
impl Part {
    fn fixed_bytes(&self) -> i64 {
        match self {
            Self::Word(_)
            | Self::WordRelative { .. }
            | Self::GlobalReference(_)
            | Self::GlobalJump(_) => 2,
            Self::LongRelative { .. }
            | Self::ProcedureReference { .. }
            | Self::PrimitiveReference { .. } => 4,
            Self::GlobalAssignment(_) => 10,
            _ => 0,
        }
    }
    fn relocation_boundary(&self) -> bool {
        matches!(
            self,
            Self::Label(_) | Self::Align { .. } | Self::Branch { .. }
        )
    }
    fn ordinary_code(&self) -> bool {
        matches!(
            self,
            Self::Word(_)
                | Self::Label(_)
                | Self::Align { .. }
                | Self::Branch { .. }
                | Self::WordRelative { .. }
                | Self::LongRelative { .. }
                | Self::Text(_)
                | Self::GvmComment(_)
        )
    }
}
struct Fixup {
    bytes_before: i64,
    part: usize,
}

#[allow(clippy::vec_box)]
pub(super) struct Assembler {
    parts: Vec<Box<Part>>,
    constants: Vec<Object>,
    fixups: Vec<Box<Fixup>>,
    labels: Vec<Rc<Label>>,
}
impl Assembler {
    pub(super) fn new() -> Self {
        Self {
            parts: vec![],
            constants: vec![],
            fixups: vec![],
            labels: vec![],
        }
    }
    fn part(&mut self, part: Part) {
        self.parts.push(Box::new(part));
    }
    pub(super) fn word(&mut self, word: i64) {
        self.part(Part::Word(word.rem_euclid(65_536) as u16));
    }
    pub(super) fn long(&mut self, word: i64) {
        self.word(upper_word(word));
        self.word(word);
    }
    pub(super) fn label(&mut self, number: usize, descriptor_position: Option<Rc<Cell<i64>>>) {
        self.part(Part::Label(Rc::new(Label {
            number,
            location: Cell::new(0),
            descriptor_position,
        })));
    }
    pub(super) fn align(&mut self, boundary: i64, offset: i64) {
        self.part(Part::Align { boundary, offset });
    }
    pub(super) fn branch(&mut self, opcode: i64, number: usize) {
        self.part(Part::Branch {
            opcode,
            target: Target::Number(number),
            wide: false,
        });
    }
    pub(super) fn word_relative(&mut self, number: usize, offset: i64) {
        self.part(Part::WordRelative {
            target: Target::Number(number),
            offset,
        });
    }
    pub(super) fn long_relative(&mut self, number: usize, offset: i64, low: i64) {
        self.part(Part::LongRelative {
            target: Target::Number(number),
            offset,
            low,
        });
    }
    pub(super) fn text(&mut self, fragments: Vec<Fragment>) {
        self.part(Part::Text(fragments));
    }
    pub(super) fn gvm_comment(&mut self, code: usize) {
        self.part(Part::GvmComment(code));
    }
    pub(super) fn global_reference(&mut self, operand: usize) {
        self.part(Part::GlobalReference(operand));
    }
    pub(super) fn global_assignment(&mut self, operand: usize) {
        self.part(Part::GlobalAssignment(operand));
    }
    pub(super) fn global_jump(&mut self, operand: usize) {
        self.part(Part::GlobalJump(operand));
    }
    pub(super) fn procedure_reference(&mut self, index: usize, offset: i64) {
        self.part(Part::ProcedureReference { index, offset });
    }
    pub(super) fn primitive_reference(&mut self, object: Object, offset: i64) {
        self.part(Part::PrimitiveReference { object, offset });
    }

    fn relocation_records(&mut self) {
        let mut bytes = 2; // The object procedure-length header precedes code.
        for (index, part) in self.parts.iter().enumerate() {
            if part.relocation_boundary() {
                self.fixups.push(Box::new(Fixup {
                    bytes_before: bytes,
                    part: index,
                }));
                bytes = 0;
                if let Part::Label(label) = &**part {
                    self.labels.insert(0, label.clone());
                }
            } else {
                bytes += part.fixed_bytes();
            }
        }
    }
    fn resolve_targets(&mut self) {
        for part in &mut self.parts {
            let target = match &mut **part {
                Part::Branch { target, .. }
                | Part::WordRelative { target, .. }
                | Part::LongRelative { target, .. } => target,
                _ => continue,
            };
            let Target::Number(number) = target else {
                continue;
            };
            let label = self
                .labels
                .iter()
                .find(|label| label.number == *number)
                .expect("assembly label definition");
            *target = Target::Label(label.clone());
        }
    }
    fn assign_locations(&self) {
        let mut location = 0;
        for fixup in &self.fixups {
            location += fixup.bytes_before;
            match &*self.parts[fixup.part] {
                Part::Label(label) => {
                    label.location.set(location);
                    if let Some(position) = &label.descriptor_position {
                        position.set((location - 2).div_euclid(8));
                    }
                }
                Part::Align { boundary, offset } => {
                    location += (offset - location).rem_euclid(*boundary)
                }
                Part::Branch { wide, .. } => location += if *wide { 4 } else { 2 },
                _ => unreachable!(),
            }
        }
    }
    fn relax_branches(&mut self) {
        loop {
            self.assign_locations();
            let (mut changed, mut location) = (false, 0);
            for fixup in &self.fixups {
                location += fixup.bytes_before;
                match &mut *self.parts[fixup.part] {
                    Part::Label(_) => (),
                    Part::Align { boundary, offset } => {
                        location += (*offset - location).rem_euclid(*boundary)
                    }
                    Part::Branch { wide: true, .. } => location += 4,
                    Part::Branch { target, wide, .. } => {
                        let distance = target.location() - location - 2;
                        if !(-128..=127).contains(&distance) || distance == 0 {
                            *wide = true;
                            changed = true;
                        }
                        // Newly widened branches still advance by their old size
                        // until the next location assignment, as in the source.
                        location += 2;
                    }
                    _ => unreachable!(),
                }
            }
            if !changed {
                break;
            }
        }
    }
    fn code_bytes(&self, part: &Part, location: i64) -> i64 {
        match part {
            Part::Align { boundary, offset } => (offset - location).rem_euclid(*boundary),
            Part::Branch { wide, .. } => {
                if *wide {
                    4
                } else {
                    2
                }
            }
            _ => part.fixed_bytes(),
        }
    }
    fn write_block(
        &self,
        first: usize,
        end: usize,
        start_location: i64,
        end_location: i64,
        output: &mut ObjectFile,
    ) {
        if end_location > start_location {
            output.word((end_location - start_location) / 2);
        }
        let mut location = start_location;
        for part in &self.parts[first..end] {
            match &**part {
                Part::Word(word) => output.word(*word as i64),
                Part::Label(_) => (),
                Part::Align { .. } => {
                    let size = self.code_bytes(part, location);
                    for _ in (0..size).step_by(2) {
                        output.word(0);
                    }
                }
                Part::Branch {
                    opcode,
                    target,
                    wide: false,
                } => output.word(*opcode + (target.location() - location - 2).rem_euclid(256)),
                Part::Branch {
                    opcode,
                    target,
                    wide: true,
                } => {
                    output.word(*opcode);
                    output.word(target.location() - location - 2);
                }
                Part::WordRelative { target, offset } => {
                    output.word(target.location() - location + offset)
                }
                Part::LongRelative {
                    target,
                    offset,
                    low,
                } => output.long((target.location() - location + offset) * 65_536 + low),
                Part::Text(fragments) => output.fragments(fragments),
                Part::GvmComment(_) => (), // Original asm-gvm output flag is false.
                _ => unreachable!(),
            }
            location += self.code_bytes(part, location);
        }
    }
    fn write_code(
        &self,
        output: &mut ObjectFile,
        generator: &Generator<'_, '_>,
        objects: &mut ObjectQueue,
    ) {
        let constant = self.labels.iter().find(|label| label.number == 0).unwrap();
        let length = constant.location.get() + self.constants.len() as i64 * 4;
        assert!(length < 32_768, "object procedure size limit");
        output.word(32_768 + length);
        let (mut first, mut start, mut location) = (0, 2, 2);
        for (index, part) in self.parts.iter().enumerate() {
            if part.ordinary_code() {
                location += self.code_bytes(part, location);
                continue;
            }
            self.write_block(first, index, start, location, output);
            match &**part {
                Part::GlobalReference(operand) => {
                    output.symbol_word(34_816, global_name(generator, *operand))
                }
                Part::GlobalAssignment(operand) => {
                    output.symbol_word(36_864, global_name(generator, *operand))
                }
                Part::GlobalJump(operand) => {
                    output.symbol_word(38_912, global_name(generator, *operand))
                }
                Part::ProcedureReference { index, offset } => {
                    output.word(49_152 + *index as i64);
                    output.word(*offset);
                }
                Part::PrimitiveReference { object, offset } => {
                    output.symbol_word(40_960, procedure_name(generator, object));
                    output.word(*offset);
                }
                Part::M68020 => output.word(32_769),
                Part::M68881 => output.word(32_770),
                _ => unreachable!(),
            }
            location += part.fixed_bytes();
            first = index + 1;
            start = location;
        }
        self.write_block(first, self.parts.len(), start, location, output);
        output.word(32_768);
        for constant in &self.constants {
            output.reference(constant, generator, objects);
        }
        output.long((self.constants.len() as i64 + 1) * 8);
    }
    pub(super) fn assemble(
        &mut self,
        output: &mut ObjectFile,
        generator: &Generator<'_, '_>,
        objects: &mut ObjectQueue,
        debug: Object,
    ) {
        self.constants.push(debug);
        self.align(4, 0);
        self.label(0, None);
        self.text(vec![Fragment::Literal("L0:")]);
        self.relocation_records();
        self.resolve_targets();
        self.relax_branches();
        self.write_code(output, generator, objects);
    }
}

fn global_name<'g>(generator: &'g Generator<'_, '_>, operand: usize) -> &'g str {
    let OperandEntry::Global(name) = generator.operands.entry(operand) else {
        unreachable!()
    };
    name
}
fn procedure_name<'g>(generator: &'g Generator<'_, '_>, object: &Object) -> &'g str {
    match object {
        Object::Primitive(id) => &generator.catalog.procedures[*id].name,
        Object::Procedure(id) => &generator.procedures[*id].name,
        _ => panic!("expected procedure object"),
    }
}

// ---- Original compact 68000 operand representation ----

#[derive(Clone)]
pub(super) enum Operand68 {
    Encoded(i64),
    Global(usize),
    Registers(Ids),
}
impl Operand68 {
    pub(super) fn data(number: i64) -> Self {
        Self::Encoded(number)
    }
    pub(super) fn address(number: i64) -> Self {
        Self::Encoded(number + 8)
    }
    pub(super) fn indirect(address: i64) -> Self {
        Self::Encoded(address + 8)
    }
    pub(super) fn postincrement(address: i64) -> Self {
        Self::Encoded(address + 16)
    }
    pub(super) fn predecrement(address: i64) -> Self {
        Self::Encoded(address + 24)
    }
    pub(super) fn displacement(address: i64, offset: i64) -> Self {
        Self::Encoded(address + 32 + offset.rem_euclid(65_536) * 8)
    }
    pub(super) fn displacement_or_indirect(address: i64, offset: i64) -> Self {
        if offset == 0 {
            Self::indirect(address)
        } else {
            Self::displacement(address, offset)
        }
    }
    pub(super) fn indexed(address: i64, index: i64, offset: i64) -> Self {
        Self::Encoded(address + 524_320 + index * 8 + offset.rem_euclid(256) * 128)
    }
    pub(super) fn floating(number: i64) -> Self {
        Self::Encoded(557_096 + number)
    }
    pub(super) fn relative(number: usize, offset: i64) -> Self {
        Self::Encoded(557_104 + offset.rem_euclid(65_536) + number as i64 * 65_536)
    }
    pub(super) fn immediate(value: i64) -> Self {
        Self::Encoded(if value < 0 { value * 2 } else { -1 - value * 2 })
    }
    pub(super) fn encoded(&self) -> i64 {
        let Self::Encoded(value) = self else {
            panic!("expected encoded machine operand");
        };
        *value
    }
    fn range(&self, low: i64, high: i64) -> bool {
        matches!(self, Self::Encoded(value) if (low..high).contains(value))
    }
    pub(super) fn data_register(&self) -> bool {
        self.range(0, 8)
    }
    pub(super) fn address_register(&self) -> bool {
        self.range(8, 16)
    }
    pub(super) fn displacement_operand(&self) -> bool {
        self.range(40, 524_328)
    }
    pub(super) fn indexed_operand(&self) -> bool {
        self.range(524_328, 557_096)
    }
    pub(super) fn floating_register(&self) -> bool {
        self.range(557_096, 557_104)
    }
    pub(super) fn relative_operand(&self) -> bool {
        matches!(self, Self::Encoded(value) if *value >= 557_104)
    }
    pub(super) fn immediate_operand(&self) -> bool {
        matches!(self, Self::Encoded(value) if *value < 0)
    }
    pub(super) fn frame_relative(&self) -> bool {
        self.displacement_operand() && self.displacement_address() == 15
    }
    pub(super) fn displacement_address(&self) -> i64 {
        self.encoded().rem_euclid(8) + 8
    }
    pub(super) fn displacement_offset(&self) -> i64 {
        ((self.encoded() - 40).div_euclid(8) + 32_768).rem_euclid(65_536) - 32_768
    }
    pub(super) fn indexed_address(&self) -> i64 {
        (self.encoded() - 524_328).rem_euclid(8) + 8
    }
    pub(super) fn indexed_register(&self) -> i64 {
        (self.encoded() - 524_328).rem_euclid(128) / 8
    }
    pub(super) fn indexed_offset(&self) -> i64 {
        ((self.encoded() - 524_328).div_euclid(128) + 128).rem_euclid(256) - 128
    }
    pub(super) fn relative_label(&self) -> usize {
        ((self.encoded() - 557_104) / 65_536) as usize
    }
    pub(super) fn relative_offset(&self) -> i64 {
        (self.encoded() - 524_336).rem_euclid(65_536) - 32_768
    }
    pub(super) fn immediate_value(&self) -> i64 {
        let value = self.encoded();
        if value % 2 == 0 {
            value.div_euclid(2)
        } else {
            (!value).div_euclid(2)
        }
    }
    pub(super) fn identical(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Encoded(first), Self::Encoded(second)) => first == second,
            (Self::Global(first), Self::Global(second)) => first == second,
            (Self::Registers(first), Self::Registers(second)) => match (&first.0, &second.0) {
                (None, None) => true,
                (Some(first), Some(second)) => Rc::ptr_eq(first, second),
                _ => false,
            },
            _ => false,
        }
    }
    fn mode_register(&self) -> i64 {
        if self.displacement_operand() {
            return 32 + self.displacement_address();
        }
        if self.indexed_operand() {
            return 40 + self.indexed_address();
        }
        if self.relative_operand() {
            return 58;
        }
        if self.immediate_operand() {
            return 60;
        }
        if matches!(self, Self::Global(_)) {
            return 46;
        }
        if self.floating_register() {
            return 0;
        }
        self.encoded()
    }
    fn register_mode(&self) -> i64 {
        let mode = self.mode_register();
        (mode.rem_euclid(8) * 8 + mode / 8) * 64
    }
    fn text(&self, generator: &Generator<'_, '_>) -> Fragment {
        const DATA: [&str; 8] = ["d0", "d1", "d2", "d3", "d4", "d5", "d6", "d7"];
        const ADDRESS: [&str; 8] = ["a0", "a1", "a2", "a3", "a4", "a5", "a6", "sp"];
        const INDIRECT: [&str; 8] = ["a0@", "a1@", "a2@", "a3@", "a4@", "a5@", "a6@", "sp@"];
        const POST: [&str; 8] = [
            "a0@+", "a1@+", "a2@+", "a3@+", "a4@+", "a5@+", "a6@+", "sp@+",
        ];
        const PRE: [&str; 8] = [
            "a0@-", "a1@-", "a2@-", "a3@-", "a4@-", "a5@-", "a6@-", "sp@-",
        ];
        const FLOAT: [&str; 8] = ["fp0", "fp1", "fp2", "fp3", "fp4", "fp5", "fp6", "fp7"];
        if self.data_register() {
            return Fragment::Literal(DATA[self.encoded() as usize]);
        }
        if self.address_register() {
            return Fragment::Literal(ADDRESS[self.encoded() as usize - 8]);
        }
        if self.range(16, 24) {
            return Fragment::Literal(INDIRECT[self.encoded() as usize - 16]);
        }
        if self.range(24, 32) {
            return Fragment::Literal(POST[self.encoded() as usize - 24]);
        }
        if self.range(32, 40) {
            return Fragment::Literal(PRE[self.encoded() as usize - 32]);
        }
        if self.displacement_operand() {
            return Fragment::Text(format!(
                "{}@({})",
                ADDRESS[self.displacement_address() as usize - 8],
                self.displacement_offset()
            ));
        }
        if self.indexed_operand() {
            let index = self.indexed_register();
            let index = if index < 8 {
                DATA[index as usize]
            } else {
                ADDRESS[index as usize - 8]
            };
            return Fragment::Text(format!(
                "{}@({},{index}:l)",
                ADDRESS[self.indexed_address() as usize - 8],
                self.indexed_offset()
            ));
        }
        if self.relative_operand() {
            let label = self.relative_label();
            let offset = self.relative_offset();
            return Fragment::Text(if offset == 0 {
                format!("L{label}")
            } else {
                format!("L{label}+{offset}")
            });
        }
        if self.immediate_operand() {
            return Fragment::Text(format!("#{}", self.immediate_value()));
        }
        if self.floating_register() {
            return Fragment::Literal(FLOAT[self.encoded() as usize - 557_096]);
        }
        match self {
            Self::Global(operand) => {
                Fragment::Text(format!("GLOB({})", global_name(generator, *operand)))
            }
            Self::Registers(registers) => {
                let mut text = "[".to_owned();
                for (index, register) in registers.values().iter().enumerate() {
                    if index > 0 {
                        text.push('/');
                    }
                    text.push_str(if *register < 8 {
                        DATA[*register]
                    } else {
                        ADDRESS[*register - 8]
                    });
                }
                text.push(']');
                Fragment::Text(text)
            }
            _ => panic!("unknown machine operand"),
        }
    }
}

// ---- Untimed complete assembler diagnostics ----

pub(super) fn probe(directives: &Datum) -> Datum {
    let mut syntax = Compiler::new();
    let catalog = Catalog::new();
    let specials = Specials {
        return_var: syntax.variable(usize::MAX, "ret", Binding::Temporary),
        closure_var: syntax.variable(usize::MAX, "closure", Binding::Temporary),
        empty_var: syntax.variable(usize::MAX, "empty", Binding::Temporary),
    };
    let mut generator = Generator::new(&mut syntax, &catalog, OperandTable::new(), specials);
    let mut assembler = Assembler::new();
    let mut descriptions = Vec::new();
    for directive in directives.list() {
        let fields = directive.list();
        match fields[0].atom() {
            "word" => assembler.word(fields[1].integer()),
            "long" => assembler.long(fields[1].integer()),
            "label" => {
                let number = fields[1].number();
                let position = fields
                    .get(2)
                    .filter(|value| value.atom() == "#t")
                    .map(|_| Rc::new(Cell::new(0)));
                if let Some(position) = &position {
                    descriptions.push((number, position.clone()));
                }
                assembler.label(number, position);
            }
            "align" => assembler.align(fields[1].integer(), fields[2].integer()),
            "branch" => assembler.branch(fields[1].integer(), fields[2].number()),
            "word-relative" => assembler.word_relative(fields[1].number(), fields[2].integer()),
            "long-relative" => assembler.long_relative(
                fields[1].number(),
                fields[2].integer(),
                fields[3].integer(),
            ),
            "text" => assembler.text(vec![Fragment::Text(fields[1].atom().to_owned())]),
            "global-reference" => {
                let operand = generator.operands.global(fields[1].atom());
                assembler.global_reference(operand);
            }
            "global-assignment" => {
                let operand = generator.operands.global(fields[1].atom());
                assembler.global_assignment(operand);
            }
            "global-jump" => {
                let operand = generator.operands.global(fields[1].atom());
                assembler.global_jump(operand);
            }
            "procedure-reference" => {
                assembler.procedure_reference(fields[1].number(), fields[2].integer())
            }
            "primitive-reference" => assembler.primitive_reference(
                Object::Primitive(catalog.lookup(fields[1].atom())),
                fields[2].integer(),
            ),
            "m68020" => assembler.part(Part::M68020),
            "m68881" => assembler.part(Part::M68881),
            _ => panic!("unknown assembly diagnostic directive"),
        }
    }
    let mut output = ObjectFile::new(true);
    assembler.assemble(
        &mut output,
        &generator,
        &mut ObjectQueue::new(),
        Object::Literal(Rc::new(atom("#f"))),
    );
    Datum::List(vec![
        Datum::List(output.lines.into_iter().map(Datum::String).collect()),
        Datum::List(
            output
                .word_audit
                .unwrap()
                .into_iter()
                .map(|word| atom(&word.to_string()))
                .collect(),
        ),
        Datum::List(
            descriptions
                .into_iter()
                .map(|(number, position)| {
                    Datum::List(vec![
                        atom(&number.to_string()),
                        atom(&position.get().to_string()),
                    ])
                })
                .collect(),
        ),
    ])
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zero_distance_and_long_branches_share_updated_label_locations() {
        let mut assembler = Assembler::new();
        assembler.branch(24_576, 1);
        assembler.label(1, None);
        assembler.branch(24_576, 2);
        for _ in 0..70 {
            assembler.word(20_081);
        }
        let position = Rc::new(Cell::new(-1));
        assembler.label(2, Some(position.clone()));
        assembler.relocation_records();
        assembler.resolve_targets();
        assembler.relax_branches();
        let Part::Branch { target, wide, .. } = &*assembler.parts[0] else {
            unreachable!()
        };
        assert!(*wide);
        assert_eq!(target.location(), 6);
        let Part::Branch { wide, .. } = &*assembler.parts[2] else {
            unreachable!()
        };
        assert!(*wide);
        assert_eq!(position.get(), 18);
    }

    #[test]
    fn source_negative_upper_word_quirk_is_preserved() {
        assert_eq!(upper_word(-65_536), -1);
        assert_eq!(upper_word(-65_537), -2);
        assert_eq!(upper_word(-131_072), -3);
    }

    #[test]
    fn compact_operands_preserve_signed_offsets_and_distinct_addressing_modes() {
        let displaced = Operand68::displacement(15, -4);
        assert!(displaced.frame_relative());
        assert_eq!(displaced.displacement_offset(), -4);
        let indexed = Operand68::indexed(9, 3, -8);
        assert_eq!(indexed.indexed_address(), 9);
        assert_eq!(indexed.indexed_register(), 3);
        assert_eq!(indexed.indexed_offset(), -8);
        let relative = Operand68::relative(17, -6);
        assert_eq!(relative.relative_label(), 17);
        assert_eq!(relative.relative_offset(), -6);
        assert!(
            !Operand68::displacement(15, 0).identical(&Operand68::displacement_or_indirect(15, 0))
        );
        for value in [-65_536, -1, 0, 1, 65_536] {
            assert_eq!(Operand68::immediate(value).immediate_value(), value);
        }
    }
}
