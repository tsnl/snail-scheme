use super::*;

// ---- Physical registers and instruction encodings ----

const DTEMP: Operand68 = Operand68::Encoded(0);
const ATEMP1: Operand68 = Operand68::Encoded(9);
const ATEMP2: Operand68 = Operand68::Encoded(10);
const HEAP: Operand68 = Operand68::Encoded(11);
const PSTATE: Operand68 = Operand68::Encoded(13);
const SP: Operand68 = Operand68::Encoded(15);
const PUSH: Operand68 = Operand68::Encoded(39);
const POP: Operand68 = Operand68::Encoded(31);
const NULL: Operand68 = Operand68::Encoded(6);
const FALSE: Operand68 = Operand68::Encoded(7);
const POLL: Operand68 = Operand68::Encoded(5);
const BITS_UNASSIGNED: i64 = -4 * 8 + 7;

#[derive(Clone, Copy)]
enum Width {
    Byte,
    Word,
    Long,
}
#[derive(Clone, Copy)]
enum Binary {
    Add,
    Subtract,
    Compare,
    And,
    Or,
    Xor,
}
#[derive(Clone, Copy)]
enum Branch {
    Always,
    CarryClear,
    CarrySet,
    Higher,
    LowerSame,
    Minus,
    Plus,
    Equal,
    NotEqual,
    Less,
    Greater,
    LessEqual,
    GreaterEqual,
}
impl Branch {
    fn encoding(self) -> (i64, &'static str) {
        match self {
            Self::Always => (24576, "bra"),
            Self::CarryClear => (25600, "bcc"),
            Self::CarrySet => (25856, "bcs"),
            Self::Higher => (25088, "bhi"),
            Self::LowerSame => (25344, "bls"),
            Self::Minus => (27392, "bmi"),
            Self::Plus => (27136, "bpl"),
            Self::Equal => (26368, "beq"),
            Self::NotEqual => (26112, "bne"),
            Self::Less => (27904, "blt"),
            Self::Greater => (28160, "bgt"),
            Self::LessEqual => (28416, "ble"),
            Self::GreaterEqual => (27648, "bge"),
        }
    }
}
fn register68(number: usize) -> Operand68 {
    if number == 0 {
        Operand68::address(0)
    } else {
        Operand68::data(number as i64)
    }
}
fn temporary_in(operand: &Operand68) -> Option<Operand68> {
    let register = if operand.data_register() || operand.address_register() {
        operand.clone()
    } else if operand.range(16, 40) || operand.displacement_operand() {
        Operand68::address(operand.encoded().rem_euclid(8))
    } else if operand.indexed_operand() {
        Operand68::Encoded(operand.indexed_register())
    } else {
        return None;
    };
    [DTEMP, ATEMP1, ATEMP2]
        .into_iter()
        .find(|r| r.identical(&register))
}
fn trap_frame_slots(slots: &Ids, delta: i64, empty: usize) -> Ids {
    let mut copied = if delta < 0 {
        ids_suffix(slots, -delta as usize)
    } else {
        slots.clone()
    };
    for _ in 0..delta.max(0) {
        copied = Ids::cons(empty, copied);
    }
    // adjust-slots copies its resulting spine even when delta is zero;
    // trap metadata never shares the original frame-slot spine.
    copied.append(&Ids::default())
}
fn pick_address(keep: Option<&Operand68>) -> Operand68 {
    if keep.is_some_and(|r| r.identical(&ATEMP1)) {
        ATEMP2
    } else {
        ATEMP1
    }
}

// ---- Per-procedure state and first-class return descriptors ----

enum VariableDescription {
    Name(String),
    Closed(Ids),
}
impl VariableDescription {
    fn equal(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Name(first), Self::Name(second)) => first == second,
            (Self::Closed(first), Self::Closed(second)) => {
                let (mut first, mut second) = (&first.0, &second.0);
                loop {
                    match (first, second) {
                        (None, None) => return true,
                        (Some(a), Some(b)) if a.id == b.id => {
                            first = &a.next.0;
                            second = &b.next.0;
                        }
                        _ => return false,
                    }
                }
            }
            _ => false,
        }
    }
}
struct FirstClassLabel {
    position: Rc<Cell<i64>>,
    source: Option<usize>,
    variables: Ids,
}
#[allow(clippy::vec_box)]
struct Emitter<'g, 's, 'a, 'o> {
    generator: &'g Generator<'s, 'a>,
    objects: &'o mut ObjectQueue,
    asm: Assembler,
    frame_size: i64,
    entry_label: usize,
    next_label: usize,
    source: Option<usize>,
    entry_frame: Rc<Frame>,
    exit_frame: Rc<Frame>,
    variables: Vec<VariableDescription>,
    labels: Vec<Box<FirstClassLabel>>,
    pointers_allocated: usize,
}
impl<'g, 's, 'a, 'o> Emitter<'g, 's, 'a, 'o> {
    fn new(generator: &'g Generator<'s, 'a>, group: usize, objects: &'o mut ObjectQueue) -> Self {
        let blocks = &generator.groups[group];
        let entry = blocks.blocks.iter().find(|&&block| matches!(generator.instructions[generator.blocks[block].label].kind, InstructionKind::Label { number, .. } if number == blocks.entry)).copied().expect("entry block");
        let frame = generator.instructions[generator.blocks[entry].label]
            .frame
            .clone();
        let number = blocks.entry;
        Self {
            generator,
            objects,
            asm: Assembler::new(),
            frame_size: 0,
            entry_label: number,
            next_label: blocks.next_label,
            source: None,
            entry_frame: frame.clone(),
            exit_frame: frame,
            variables: vec![],
            labels: vec![],
            pointers_allocated: 0,
        }
    }
    fn fresh_label(&mut self) -> usize {
        let label = self.next_label;
        self.next_label += 1;
        label
    }
    fn variable_description(&mut self, description: VariableDescription) -> usize {
        if let Some(index) = self.variables.iter().position(|d| d.equal(&description)) {
            return index;
        }
        let index = self.variables.len();
        self.variables.push(description);
        index
    }
    fn live(&self, variable: usize, frame: &Frame) -> bool {
        frame.live.has(variable)
            || (variable == self.generator.specials.closure_var
                && !frame.closed.intersection(&frame.live).empty())
    }
    fn first_class_label(&mut self, slots: &Ids, frame: &Frame) -> Rc<Cell<i64>> {
        let mut variables = Ids::default();
        for (index, variable) in slots.values().into_iter().enumerate() {
            if !self.live(variable, frame) {
                continue;
            }
            let description = if variable == self.generator.specials.closure_var {
                let indices: Vec<_> = frame
                    .closed
                    .values()
                    .iter()
                    .map(|&v| {
                        self.variable_description(VariableDescription::Name(
                            self.generator.syntax.variables[v].name.clone(),
                        ))
                    })
                    .collect();
                VariableDescription::Closed(Ids::from_slice(&indices))
            } else {
                let var = &self.generator.syntax.variables[variable];
                if var.binding == Binding::Temporary {
                    continue;
                }
                VariableDescription::Name(var.name.clone())
            };
            let descriptor = self.variable_description(description);
            variables = Ids::cons(index * 16384 + descriptor, variables);
        }
        let position = Rc::new(Cell::new(0));
        self.labels.push(Box::new(FirstClassLabel {
            position: position.clone(),
            source: self.source,
            variables,
        }));
        position
    }

    // Each instruction emits its word/extensions and readable assembly atomically.
    fn instruction_text(&mut self, mnemonic: &'static str, operands: &[Operand68]) {
        let mut fragments = vec![Fragment::Literal(" "), Fragment::Literal(mnemonic)];
        if !operands.is_empty() {
            fragments.push(Fragment::Literal(" "));
        }
        for (index, operand) in operands.iter().enumerate() {
            if index != 0 {
                fragments.push(Fragment::Literal(","));
            }
            fragments.push(operand.text(self.generator));
        }
        self.asm.text(fragments);
    }
    fn extension(&mut self, operand: &Operand68, write: bool, width: Width) {
        if operand.displacement_operand() {
            self.asm.word(operand.displacement_offset());
        } else if operand.indexed_operand() {
            self.asm.word(
                operand.indexed_register() * 4096 + 2048 + operand.indexed_offset().rem_euclid(256),
            );
        } else if operand.relative_operand() {
            self.asm
                .word_relative(operand.relative_label(), operand.relative_offset());
        } else if operand.immediate_operand() {
            match width {
                Width::Long => self.asm.long(operand.immediate_value()),
                _ => self.asm.word(operand.immediate_value()),
            }
        } else if let Operand68::Global(global) = operand {
            if write {
                self.asm.global_assignment(*global);
            } else {
                self.asm.global_reference(*global);
            }
        }
    }
    fn move_value(&mut self, source: &Operand68, destination: &Operand68, width: Width) {
        let (opcode, mnemonic) = match width {
            Width::Byte => (4096, "movb"),
            Width::Word => (12288, "movw"),
            Width::Long => (8192, "movl"),
        };
        self.asm
            .word(opcode + destination.register_mode() + source.mode_register());
        self.extension(source, false, width);
        self.extension(destination, true, width);
        self.instruction_text(mnemonic, &[source.clone(), destination.clone()]);
    }
    fn move_quick(&mut self, value: i64, destination: &Operand68) {
        self.asm
            .word(28672 + destination.encoded() * 512 + value.rem_euclid(256));
        self.instruction_text("moveq", &[Operand68::immediate(value), destination.clone()]);
    }
    fn binary(
        &mut self,
        operation: Binary,
        source: &Operand68,
        destination: &Operand68,
        width: Width,
    ) {
        let word = matches!(width, Width::Word);
        let byte = matches!(width, Width::Byte);
        let (address, immediate, to_data, from_data, mnemonic) = match operation {
            Binary::Add if word => (53440, 1600, 53312, 53568, "addw"),
            Binary::Add => (53696, 1664, 53376, 53632, "addl"),
            Binary::Subtract if word => (37056, 1088, 36928, 37184, "subw"),
            Binary::Subtract => (37312, 1152, 36992, 37248, "subl"),
            Binary::Compare if byte => (0, 3072, 45056, 0, "cmpb"),
            Binary::Compare if word => (45248, 3136, 45120, 0, "cmpw"),
            Binary::Compare => (45504, 3200, 45184, 0, "cmpl"),
            Binary::And if word => (0, 576, 49216, 49472, "andw"),
            Binary::And => (0, 640, 49280, 49536, "andl"),
            Binary::Or => (0, 128, 32896, 33152, "orl"),
            Binary::Xor => (0, 2688, 0, 45440, "eorl"),
        };
        if address != 0 && destination.address_register() {
            self.asm
                .word(address + (destination.encoded() - 8) * 512 + source.mode_register());
            self.extension(source, false, width);
        } else if source.immediate_operand() {
            self.asm.word(immediate + destination.mode_register());
            self.extension(source, false, width);
            self.extension(destination, !matches!(operation, Binary::Compare), width);
        } else if matches!(operation, Binary::Compare)
            || (destination.data_register() && !matches!(operation, Binary::Xor))
        {
            self.asm
                .word(to_data + destination.encoded() * 512 + source.mode_register());
            self.extension(source, false, width);
        } else {
            self.asm
                .word(from_data + source.encoded() * 512 + destination.mode_register());
            self.extension(destination, true, width);
        }
        self.instruction_text(mnemonic, &[source.clone(), destination.clone()]);
    }
    fn quick(&mut self, value: i64, destination: &Operand68, subtract: bool, width: Width) {
        let (opcode, name) = match (subtract, width) {
            (false, Width::Word) => (20544, "addqw"),
            (false, _) => (20608, "addql"),
            (true, Width::Word) => (20800, "subqw"),
            (true, _) => (20864, "subql"),
        };
        self.asm.word(
            opcode + (if value == 8 { 0 } else { value }) * 512 + destination.mode_register(),
        );
        self.extension(destination, true, width);
        self.instruction_text(name, &[Operand68::immediate(value), destination.clone()]);
    }
    fn clear(&mut self, destination: &Operand68) {
        self.asm.word(17024 + destination.mode_register());
        self.extension(destination, true, Width::Long);
        self.instruction_text("clrl", std::slice::from_ref(destination));
    }
    fn negate(&mut self, destination: &Operand68) {
        self.asm.word(17536 + destination.mode_register());
        self.extension(destination, true, Width::Long);
        self.instruction_text("negl", std::slice::from_ref(destination));
    }
    fn lea(&mut self, source: &Operand68, destination: &Operand68) {
        self.asm
            .word(16832 + (destination.encoded() - 8) * 512 + source.mode_register());
        self.extension(source, false, Width::Long);
        self.instruction_text("lea", &[source.clone(), destination.clone()]);
    }
    fn shift(&mut self, source: &Operand68, destination: &Operand68, right: bool, logical: bool) {
        let (opcode, mnemonic) = match (right, logical) {
            (false, false) => (57728, "asll"),
            (true, false) => (57472, "asrl"),
            (false, true) => (57736, "lsll"),
            (true, true) => (57480, "lsrl"),
        };
        let count = if source.data_register() {
            source.encoded()
        } else {
            let n = source.immediate_value();
            if n == 8 { 0 } else { n }
        };
        self.asm.word(
            opcode
                + if source.data_register() { 32 } else { 0 }
                + count * 512
                + destination.encoded(),
        );
        self.instruction_text(mnemonic, &[source.clone(), destination.clone()]);
    }
    fn branch(&mut self, branch: Branch, label: usize) {
        let (opcode, mnemonic) = branch.encoding();
        self.asm.branch(opcode, label);
        self.asm.text(vec![
            Fragment::Literal(" "),
            Fragment::Literal(mnemonic),
            Fragment::Literal(" L"),
            Fragment::Number(label as i64),
        ]);
    }
    fn label(&mut self, label: usize) {
        self.asm.label(label, None);
        self.asm.text(vec![
            Fragment::Literal("L"),
            Fragment::Number(label as i64),
            Fragment::Literal(":"),
        ]);
    }
    fn bit_test(&mut self, bit: &Operand68, operand: &Operand68) {
        self.asm
            .word(256 + bit.encoded() * 512 + operand.mode_register());
        self.extension(operand, false, Width::Word);
        self.instruction_text("btst", &[bit.clone(), operand.clone()]);
    }
    fn dbra(&mut self, register: &Operand68, label: usize) {
        self.asm.word(20936 + register.encoded());
        self.asm.word_relative(label, 0);
        self.asm.text(vec![
            Fragment::Literal(" dbra "),
            register.text(self.generator),
            Fragment::Literal(",L"),
            Fragment::Number(label as i64),
        ]);
    }
    fn trap(&mut self, kind: usize, number: i64, arguments: &[i64]) {
        self.asm.word(if kind == 3 { 20206 } else { 20142 });
        self.asm.word(32768 + (number - 32) * 8);
        if kind == 2 {
            self.asm
                .align(8, (4 - arguments.len() as i64 * 2).rem_euclid(8));
        }
        for &word in arguments {
            self.asm.word(word);
        }
        let mut fragments = vec![
            Fragment::Literal(match kind {
                1 => " TRAP1(",
                2 => " TRAP2(",
                _ => " TRAP3(",
            }),
            Fragment::Number(number),
        ];
        for &word in arguments {
            fragments.push(Fragment::Literal(","));
            fragments.push(Fragment::Number(word));
        }
        fragments.push(Fragment::Literal(")"));
        self.asm.text(fragments);
    }
    fn jump_address(&mut self, address: &Operand68) {
        self.asm.word(20160 + address.mode_register());
        self.extension(address, false, Width::Long);
        self.instruction_text("jmp", std::slice::from_ref(address));
    }
    fn move_procedure(&mut self, object: Object, index: Option<usize>, destination: &Operand68) {
        self.asm.word(8192 + destination.register_mode() + 60);
        let prefix = if let Some(index) = index {
            self.asm.procedure_reference(index, 0);
            vec![
                Fragment::Literal(" MOVE_PROC("),
                Fragment::Number(index as i64),
            ]
        } else {
            let name = procedure_name(self.generator, &object).to_owned();
            self.asm.primitive_reference(object, 0);
            vec![Fragment::Literal(" MOVE_PRIM("), Fragment::Text(name)]
        };
        self.extension(destination, true, Width::Long);
        let mut fragments = prefix;
        fragments.extend([
            Fragment::Literal(","),
            destination.text(self.generator),
            Fragment::Literal(")"),
        ]);
        self.asm.text(fragments);
    }
    fn jump_procedure(&mut self, object: Object, index: Option<usize>, offset: i64) {
        self.asm.word(20217);
        let mut fragments = if let Some(index) = index {
            self.asm.procedure_reference(index, offset);
            vec![
                Fragment::Literal(" JMP_PROC("),
                Fragment::Number(index as i64),
            ]
        } else {
            let name = procedure_name(self.generator, &object).to_owned();
            self.asm.primitive_reference(object, offset);
            vec![Fragment::Literal(" JMP_PRIM("), Fragment::Text(name)]
        };
        fragments.extend([
            Fragment::Literal(","),
            Fragment::Number(offset),
            Fragment::Literal(")"),
        ]);
        self.asm.text(fragments);
    }

    // ---- Source value moves and logical stack-slot lifetime ----

    fn move_number(&mut self, number: i64, destination: &Operand68) {
        if number == BITS_NULL {
            self.move_value(&NULL, destination, Width::Long);
        } else if number == BITS_FALSE {
            self.move_value(&FALSE, destination, Width::Long);
        } else if destination.data_register() && (-128..=127).contains(&number) {
            self.move_quick(number, destination);
        } else if destination.address_register() && (-32768..=32767).contains(&number) {
            self.move_value(&Operand68::immediate(number), destination, Width::Word);
        } else if destination.identical(&PUSH) && (-32768..=32767).contains(&number) {
            self.asm.word(18552);
            self.asm.word(number);
            self.asm
                .text(vec![Fragment::Literal(" pea "), Fragment::Number(number)]);
        } else if number == 0 {
            self.clear(destination);
        } else if (-128..=127).contains(&number)
            && !(destination.indexed_operand() && destination.indexed_register() == 0)
        {
            self.move_quick(number, &DTEMP);
            self.move_value(&DTEMP, destination, Width::Long);
        } else {
            self.move_value(&Operand68::immediate(number), destination, Width::Long);
        }
    }
    fn move_operand68(&mut self, source: &Operand68, destination: &Operand68) {
        if source.identical(destination) {
            return;
        }
        if source.immediate_operand() {
            self.move_number(source.immediate_value(), destination);
        } else {
            self.move_value(source, destination, Width::Long);
        }
    }
    fn add_number(&mut self, number: i64, destination: &Operand68) {
        if number == 0 {
            return;
        }
        if (-8..=8).contains(&number) {
            self.quick(number.abs(), destination, number < 0, Width::Long);
        } else if destination.address_register() && (-32768..=32767).contains(&number) {
            self.lea(
                &Operand68::displacement(destination.encoded(), number),
                destination,
            );
        } else if !destination.identical(&DTEMP) && (-128..=128).contains(&number) {
            self.move_quick(-number.abs(), &DTEMP);
            self.binary(
                if number > 0 {
                    Binary::Subtract
                } else {
                    Binary::Add
                },
                &DTEMP,
                destination,
                Width::Long,
            );
        } else {
            self.binary(
                Binary::Add,
                &Operand68::immediate(number),
                destination,
                Width::Long,
            );
        }
    }
    fn stack_needed(&self, operand: usize, needed: usize) -> usize {
        if stack(operand) {
            needed.max(operand % 10000)
        } else if let Some((base, _)) = self.generator.operands.entry_if_closure(operand) {
            self.stack_needed(base, needed)
        } else {
            needed
        }
    }
    fn operands_needed(&self, operands: &[usize], needed: usize) -> usize {
        operands
            .iter()
            .fold(needed, |n, &op| self.stack_needed(op, n))
    }
    fn machine_needed(&self, operand: &Operand68, needed: usize) -> usize {
        if operand.frame_relative() {
            needed.max(operand.displacement_offset() as usize)
        } else if operand.identical(&PUSH) {
            needed.max((self.frame_size + 1) as usize)
        } else if operand.identical(&POP) {
            needed.max(self.frame_size as usize)
        } else {
            needed
        }
    }
    fn resize_frame(&mut self, size: usize) {
        let difference = size as i64 - self.frame_size;
        self.frame_size += difference;
        self.add_number(-4 * difference, &SP);
    }
    fn shrink_frame(&mut self, size: usize) {
        assert!(
            size as i64 <= self.frame_size,
            "cannot grow while shrinking a frame"
        );
        if size as i64 != self.frame_size {
            self.resize_frame(size);
        }
    }
    fn top_of_frame(&mut self, slot: usize, needed: usize) {
        if (slot as i64) < self.frame_size && slot >= needed {
            self.resize_frame(slot);
        }
    }
    fn top_for_operand(&mut self, operand: &Operand68, needed: usize) {
        if operand.frame_relative() {
            self.top_of_frame(operand.displacement_offset() as usize, needed);
        }
    }
    fn top_for_operands(&mut self, first: &Operand68, second: &Operand68, needed: usize) {
        if first.frame_relative() && second.frame_relative() {
            self.top_of_frame(
                first
                    .displacement_offset()
                    .max(second.displacement_offset()) as usize,
                needed,
            );
        } else {
            self.top_for_operand(first, needed);
            self.top_for_operand(second, needed);
        }
    }
    fn true_operand(&mut self, operand: &Operand68, needed: usize) -> Operand68 {
        if !operand.frame_relative() {
            return operand.clone();
        }
        let slot = operand.displacement_offset();
        if slot > self.frame_size {
            self.frame_size += 1;
            PUSH
        } else if slot == self.frame_size && (needed as i64) < self.frame_size {
            self.frame_size -= 1;
            POP
        } else {
            Operand68::displacement_or_indirect(15, 4 * (self.frame_size - slot))
        }
    }
    fn closure_operand(
        &mut self,
        operand: usize,
        keep: Option<&Operand68>,
        needed: usize,
        read: bool,
    ) -> Operand68 {
        let (base, index) = self.generator.operands.entry_if_closure(operand).unwrap();
        let offset = index as i64 * 4 + 2;
        if read && base / 10000 == 2 {
            return Operand68::relative(base % 10000, offset);
        }
        if base == 0 {
            return Operand68::displacement_or_indirect(8, offset);
        }
        let address = pick_address(keep);
        if base / 10000 == 5 {
            let OperandEntry::Object(object) = self.generator.operands.entry(base) else {
                unreachable!()
            };
            let object = object.clone();
            if let Some(number) = object_encoding(&object) {
                self.move_number(number, &address);
            } else {
                let constant = self.constant(object);
                self.move_value(&constant, &address, Width::Long);
            }
        } else {
            self.move_to_machine(base, &address, needed);
        }
        Operand68::displacement_or_indirect(address.encoded(), offset)
    }
    fn constant(&mut self, object: Object) -> Operand68 {
        let index = if let Some(index) = self
            .asm
            .constants
            .iter()
            .position(|c| object_eqv(c, &object))
        {
            index
        } else {
            let index = self.asm.constants.len();
            self.asm.constants.push(object);
            index
        };
        Operand68::relative(0, index as i64 * 4)
    }
    fn operand68(&mut self, operand: usize, keep: Option<&Operand68>, needed: usize) -> Operand68 {
        match operand / 10000 {
            2 => {
                let address = pick_address(keep);
                self.lea(&Operand68::relative(operand % 10000, 0), &address);
                address
            }
            4 => self.closure_operand(operand, keep, needed, true),
            5 => {
                let OperandEntry::Object(object) = self.generator.operands.entry(operand) else {
                    unreachable!()
                };
                let object = object.clone();
                if matches!(object, Object::Procedure(_) | Object::Primitive(_)) {
                    let index = self.objects.add(object.clone(), self.generator);
                    let address = pick_address(keep);
                    self.move_procedure(object, index, &address);
                    address
                } else if let Some(number) = object_encoding(&object) {
                    Operand68::immediate(number)
                } else {
                    self.constant(object)
                }
            }
            _ => self.location68(operand, keep, needed),
        }
    }
    fn location68(
        &mut self,
        location: usize,
        keep: Option<&Operand68>,
        needed: usize,
    ) -> Operand68 {
        match location / 10000 {
            0 => register68(location),
            1 => Operand68::displacement(15, (location % 10000) as i64),
            3 => Operand68::Global(location),
            4 => self.closure_operand(location, keep, needed, false),
            _ => panic!("invalid target location"),
        }
    }
    fn move_to_location(&mut self, operand: &Operand68, location: usize, needed: usize) {
        match location / 10000 {
            0 => {
                self.top_for_operand(operand, needed);
                let operand = self.true_operand(operand, needed);
                self.move_operand68(&operand, &register68(location));
            }
            1 => {
                let slot = location % 10000;
                let after = if slot < needed { needed } else { slot - 1 };
                if self.frame_size > slot as i64 {
                    let top = if operand.frame_relative()
                        && operand.displacement_offset() >= slot as i64 - 1
                    {
                        operand.displacement_offset() as usize
                    } else {
                        slot
                    };
                    self.top_of_frame(top, after);
                }
                let source = self.true_operand(operand, after);
                let destination =
                    self.true_operand(&Operand68::displacement(15, slot as i64), needed);
                self.move_operand68(&source, &destination);
            }
            3 => {
                self.top_for_operand(operand, needed);
                let source = self.true_operand(operand, needed);
                self.move_operand68(&source, &Operand68::Global(location));
            }
            4 => {
                let closure = self.closure_operand(
                    location,
                    temporary_in(operand).as_ref(),
                    self.machine_needed(operand, needed),
                    false,
                );
                self.top_for_operand(operand, needed);
                let source = self.true_operand(operand, needed);
                self.move_operand68(&source, &closure);
            }
            _ => panic!("invalid target destination"),
        }
    }
    fn move_to_machine(&mut self, operand: usize, destination: &Operand68, needed: usize) {
        if operand / 10000 == 2 && destination.address_register() {
            self.lea(&Operand68::relative(operand % 10000, 0), destination);
            return;
        }
        let after = self.machine_needed(destination, needed);
        let source = self.operand68(operand, temporary_in(destination).as_ref(), after);
        self.top_for_operands(&source, destination, needed);
        let source = self.true_operand(&source, after);
        let destination = self.true_operand(destination, needed);
        self.move_operand68(&source, &destination);
    }
    fn copy(&mut self, operand: usize, location: usize, needed: usize) {
        if operand / 10000 == 2 && location == 0 {
            self.lea(&Operand68::relative(operand % 10000, 0), &register68(0));
        } else {
            let source = self.operand68(operand, None, self.stack_needed(location, needed));
            self.move_to_location(&source, location, needed);
        }
    }
}

// ---- Entry checks, trap roots and return descriptors ----

impl Emitter<'_, '_, '_, '_> {
    fn label_pointer(&mut self, label: usize) {
        self.asm.word_relative(label, 0);
        self.asm.text(vec![
            Fragment::Literal(" LBL_PTR(L"),
            Fragment::Number(label as i64),
            Fragment::Literal(")"),
        ]);
    }
    fn return_label(&mut self, label: usize, slots: &Ids, extra: usize, frame: &Frame) {
        let index = ids_position(slots, self.generator.specials.return_var)
            .expect("return address in frame");
        let size = slots.values().len();
        let link = size - index;
        let descriptor = self.first_class_label(slots, frame);
        self.asm.align(8, 4);
        self.asm.word((size + extra) as i64 * 4);
        self.asm.word((size + extra - link) as i64 * 4);
        self.asm.word_relative(self.entry_label, 32766);
        self.asm.label(label, Some(descriptor));
        self.asm.text(vec![
            Fragment::Literal(" RETURN(L"),
            Fragment::Number(self.entry_label as i64),
            Fragment::Literal(","),
            Fragment::Number((size + extra) as i64),
            Fragment::Literal(","),
            Fragment::Number(link as i64),
            Fragment::Literal(")"),
        ]);
        self.asm.text(vec![
            Fragment::Literal("L"),
            Fragment::Number(label as i64),
            Fragment::Literal(":"),
        ]);
    }
    fn entry(&mut self, label: usize, parameters: usize, minimum: usize, rest: bool, closed: bool) {
        let frame = self.exit_frame.clone();
        let descriptor = self.first_class_label(&Ids::default(), &frame);
        if label == self.entry_label {
            self.label(label);
        } else {
            self.asm.align(8, 0);
            self.asm.word_relative(self.entry_label, 32766);
            self.asm.label(label, Some(descriptor));
            self.asm.text(vec![
                Fragment::Literal(" SUBPROC(L"),
                Fragment::Number(self.entry_label as i64),
                Fragment::Literal(")"),
            ]);
            self.asm.text(vec![
                Fragment::Literal("L"),
                Fragment::Number(label as i64),
                Fragment::Literal(":"),
            ]);
        }
        let fixed = if rest { parameters - 1 } else { parameters };
        let mut optional = vec![0; parameters - minimum + 1];
        let mut dispatch = optional.clone();
        for count in minimum..=parameters {
            let label = self.fresh_label();
            optional[parameters - count] = label;
            dispatch[parameters - count] = if count >= parameters || parameters <= 3 {
                label
            } else {
                self.fresh_label()
            };
        }
        if closed {
            let closure = register68(4);
            self.move_value(&POP, &closure, Width::Long);
            self.quick(6, &closure, true, Width::Long);
            if (minimum <= 1 && 1 <= fixed) || (minimum <= 2 && 2 <= fixed) {
                self.move_value(&DTEMP, &DTEMP, Width::Word);
            }
        }
        if minimum <= 2 && 2 <= fixed {
            self.branch(Branch::Equal, dispatch[parameters - 2]);
        }
        if minimum <= 1 && 1 <= fixed {
            self.branch(Branch::Minus, dispatch[parameters - 1]);
        }
        for count in minimum..=fixed {
            if count == 1 || count == 2 {
                continue;
            }
            self.binary(
                Binary::Compare,
                &Operand68::immediate(argument_count(count)),
                &DTEMP,
                Width::Word,
            );
            self.branch(Branch::Equal, dispatch[parameters - count]);
        }
        let (trap, arguments) = if rest {
            (
                if closed { 8 } else { 7 },
                vec![minimum as i64, fixed as i64],
            )
        } else if minimum == fixed {
            (if closed { 10 } else { 9 }, vec![fixed as i64])
        } else {
            (
                if closed { 12 } else { 11 },
                vec![minimum as i64, fixed as i64],
            )
        };
        self.trap(1, trap, &arguments);
        if !closed {
            self.label_pointer(label);
        }
        if rest {
            self.pointers_allocated = 1;
            self.guarantee_fudge();
            self.branch(Branch::Always, optional[0]);
        }
        if parameters > 3 {
            for count in (minimum..parameters).rev() {
                let stacked = count.saturating_sub(3);
                self.label(dispatch[parameters - count]);
                let mut register = 1;
                while register <= 3 && register <= count && register <= parameters - 3 - stacked {
                    self.move_value(&register68(register), &PUSH, Width::Long);
                    register += 1;
                }
                for old in register..=count.min(3) {
                    self.move_value(
                        &register68(old),
                        &register68(old - register + 1),
                        Width::Long,
                    );
                }
                if count > minimum {
                    self.branch(Branch::Always, optional[parameters - count]);
                }
            }
        }
        for count in minimum..=parameters {
            let value = if count == fixed {
                BITS_NULL
            } else {
                BITS_UNASSIGNED
            };
            self.label(optional[parameters - count]);
            if parameters - count > 3 {
                self.move_number(value, &PUSH);
            } else if count < parameters {
                self.move_number(
                    value,
                    &register68(if parameters <= 3 {
                        count + 1
                    } else {
                        count + 4 - parameters
                    }),
                );
            }
        }
    }
    fn register_save(&mut self, registers: &[i64], restore: bool) {
        let memory = if restore { POP } else { PUSH };
        let mask = registers
            .iter()
            .fold(0, |mask, &r| mask | (1 << if restore { r } else { 15 - r }));
        self.asm
            .word(if restore { 19648 } else { 18624 } + memory.mode_register());
        self.asm.word(mask);
        let list = Operand68::Registers(Ids::from_slice(
            &registers.iter().map(|&r| r as usize).collect::<Vec<_>>(),
        ));
        let operands = if restore {
            [memory, list]
        } else {
            [list, memory]
        };
        self.instruction_text("moveml", &operands);
    }
    fn trap_return(
        &mut self,
        frame: Rc<Frame>,
        save_live: bool,
        not_saved: Option<&Operand68>,
        number: i64,
        continuation: usize,
    ) {
        let return_slot = frame
            .slots
            .values()
            .iter()
            .rev()
            .position(|&v| !self.live(v, &frame))
            .map(|index| index + 1)
            .unwrap_or(frame.size + 1);
        let mut saved = vec![];
        let mut saved_return = None;
        for (index, variable) in frame.registers.values().into_iter().enumerate() {
            let register = register68(index);
            if variable == self.generator.specials.return_var {
                if return_slot as i64 > self.frame_size {
                    saved.push((register.encoded(), variable));
                } else {
                    saved_return = Some((register, variable));
                }
            } else if save_live
                && self.live(variable, &frame)
                && !not_saved.is_some_and(|r| r.identical(&register))
            {
                saved.push((register.encoded(), variable));
            }
        }
        saved.sort_by_key(|&(register, _)| register);
        let base = trap_frame_slots(
            &frame.slots,
            self.frame_size - frame.size as i64,
            self.generator.specials.empty_var,
        );
        let mut slots = Ids::from_slice(
            &saved
                .iter()
                .map(|&(_, variable)| variable)
                .collect::<Vec<_>>(),
        )
        .append(&base);
        if let Some((register, variable)) = &saved_return {
            self.move_value(
                register,
                &Operand68::displacement_or_indirect(
                    15,
                    4 * (self.frame_size - return_slot as i64),
                ),
                Width::Long,
            );
            let index = slots.values().len() - return_slot;
            slots = ids_replace(&slots, index, *variable, self.generator.specials.empty_var);
        }
        let registers: Vec<_> = saved.iter().map(|&(register, _)| register).collect();
        if registers.len() > 2 {
            self.register_save(&registers, false);
        } else {
            for &register in registers.iter().rev() {
                self.move_value(&Operand68::Encoded(register), &PUSH, Width::Long);
            }
        }
        self.trap(2, number, &[]);
        let label = self.fresh_label();
        self.return_label(label, &slots, 0, &frame);
        if registers.len() > 2 {
            self.register_save(&registers, true);
        } else {
            for &register in &registers {
                self.move_value(&POP, &Operand68::Encoded(register), Width::Long);
            }
        }
        if let Some((register, _)) = saved_return {
            self.move_value(
                &Operand68::displacement_or_indirect(
                    15,
                    4 * (self.frame_size - return_slot as i64),
                ),
                &register,
                Width::Long,
            );
        }
        self.label(continuation);
    }
    fn poll(&mut self) {
        let label = self.fresh_label();
        self.dbra(&POLL, label);
        self.move_quick(9, &POLL);
        self.binary(
            Binary::Compare,
            &Operand68::indirect(PSTATE.encoded()),
            &SP,
            Width::Long,
        );
        self.branch(Branch::CarryClear, label);
        self.trap_return(self.entry_frame.clone(), false, None, 24, label);
    }
    fn poll_branch(&mut self, label: usize) {
        self.dbra(&POLL, label);
        self.move_quick(9, &POLL);
        self.binary(
            Binary::Compare,
            &Operand68::indirect(PSTATE.encoded()),
            &SP,
            Width::Long,
        );
        self.branch(Branch::CarryClear, label);
        let continuation = self.fresh_label();
        self.trap_return(self.entry_frame.clone(), false, None, 24, continuation);
        self.branch(Branch::Always, label);
    }
    fn guarantee_fudge(&mut self) {
        if self.pointers_allocated == 0 {
            return;
        }
        let label = self.fresh_label();
        self.binary(
            Binary::Compare,
            &Operand68::displacement(13, 48),
            &HEAP,
            Width::Long,
        );
        self.branch(Branch::CarryClear, label);
        self.trap_return(self.entry_frame.clone(), false, None, 13, label);
        self.pointers_allocated = 0;
    }
    fn guarantee_space(&mut self, pointers: usize) {
        self.pointers_allocated += pointers;
        if self.pointers_allocated > 4 * (2 * 1024 + 1024) {
            self.guarantee_fudge();
            self.pointers_allocated = pointers;
        }
    }
}
fn argument_count(count: usize) -> i64 {
    match count {
        1 => -1,
        2 => 0,
        _ => count as i64 + 1,
    }
}

// ---- Calls, jumps and ordered instruction emission ----

impl Emitter<'_, '_, '_, '_> {
    fn setup_jump(&mut self, size: usize, arguments: Option<usize>) {
        self.shrink_frame(size);
        if let Some(count) = arguments {
            self.move_number(argument_count(count), &DTEMP);
        }
    }
    fn direct_entry_offset(&self, object: &Object, arguments: Option<usize>) -> i64 {
        let pattern = match object {
            Object::Procedure(id) => &self.generator.procedures[*id].pattern,
            Object::Primitive(id) => &self.generator.catalog.procedures[*id].pattern,
            _ => return 0,
        };
        let Datum::List(counts) = pattern else {
            return 0;
        };
        if counts.len() != 1 || arguments != Some(counts[0].number()) {
            return 0;
        }
        if counts[0].number() == 1 || counts[0].number() == 2 {
            10
        } else {
            14
        }
    }
    fn indirect_jump(&mut self, operand: &Operand68, size: usize, arguments: Option<usize>) {
        if let Some(count) = arguments {
            let label = self.fresh_label();
            self.top_for_operand(operand, size);
            let source = self.true_operand(operand, size);
            self.move_operand68(&source, &ATEMP1);
            self.shrink_frame(size);
            self.move_value(&ATEMP1, &DTEMP, Width::Long);
            self.quick(2, &DTEMP, false, Width::Word);
            self.bit_test(&DTEMP, &FALSE);
            self.branch(Branch::Equal, label);
            self.move_number(argument_count(count), &DTEMP);
            self.trap(3, 6, &[]);
            self.label(label);
            self.move_number(argument_count(count), &DTEMP);
            self.jump_address(&Operand68::indirect(9));
        } else {
            let address = if operand.address_register() {
                operand.clone()
            } else {
                self.top_for_operand(operand, size);
                let source = self.true_operand(operand, size);
                self.move_operand68(&source, &ATEMP1);
                ATEMP1
            };
            self.setup_jump(size, arguments);
            self.jump_address(&Operand68::indirect(address.encoded()));
        }
    }
    fn jump(&mut self, operand: usize, arguments: Option<usize>, poll: bool, next: Option<usize>) {
        let size = self.exit_frame.size;
        self.guarantee_fudge();
        match operand / 10000 {
            3 => {
                if poll {
                    self.poll();
                }
                self.setup_jump(size, arguments);
                self.asm.word(8814);
                self.asm.global_jump(operand);
                self.asm.word(20177);
                self.asm.text(vec![
                    Fragment::Literal(" JMP_GLOB("),
                    Fragment::Text(global_name(self.generator, operand).to_owned()),
                    Fragment::Literal(")"),
                ]);
            }
            1 if operand % 10000 == size + 1 && arguments.is_none() => {
                if poll {
                    self.poll();
                }
                self.setup_jump(size + 1, None);
                self.asm.word(20085);
                self.instruction_text("rts", &[]);
            }
            2 => {
                let label = operand % 10000;
                if poll
                    && size as i64 == self.frame_size
                    && arguments.is_none()
                    && next != Some(label)
                {
                    self.poll_branch(label);
                } else {
                    if poll {
                        self.poll();
                    }
                    self.setup_jump(size, arguments);
                    if next != Some(label) {
                        self.branch(Branch::Always, label);
                    }
                }
            }
            5 => {
                if poll {
                    self.poll();
                }
                let OperandEntry::Object(object) = self.generator.operands.entry(operand) else {
                    unreachable!()
                };
                let object = object.clone();
                if matches!(object, Object::Procedure(_) | Object::Primitive(_)) {
                    let index = self.objects.add(object.clone(), self.generator);
                    let offset = self.direct_entry_offset(&object, arguments);
                    self.setup_jump(size, if offset <= 0 { arguments } else { None });
                    self.jump_procedure(object, index, offset);
                } else {
                    let source = self.operand68(operand, None, size);
                    self.indirect_jump(&source, size, arguments);
                }
            }
            _ => {
                if poll {
                    self.poll();
                }
                let source = self.operand68(operand, None, size);
                self.indirect_jump(&source, size, arguments);
            }
        }
    }
    fn instruction(
        &mut self,
        previous: Option<usize>,
        current: usize,
        next: Option<usize>,
        needed: usize,
    ) {
        let instruction = &self.generator.instructions[current];
        self.source = instruction.source;
        self.exit_frame = instruction.frame.clone();
        self.entry_frame = previous
            .map(|id| self.generator.instructions[id].frame.clone())
            .unwrap_or_else(|| self.exit_frame.clone());
        let next_label = next.and_then(|id| match self.generator.instructions[id].kind {
            InstructionKind::Label {
                number,
                kind: LabelKind::Simple | LabelKind::TaskEntry,
            } => Some(number),
            _ => None,
        });
        match &instruction.kind {
            InstructionKind::Label { number, kind } => {
                self.entry_frame = self.exit_frame.clone();
                self.frame_size = self.exit_frame.size as i64;
                self.pointers_allocated = 0;
                match kind {
                    LabelKind::Simple => self.label(*number),
                    LabelKind::Entry {
                        parameters,
                        minimum,
                        rest,
                        closed,
                    } => self.entry(*number, *parameters, *minimum, *rest, *closed),
                    LabelKind::Return => {
                        let frame = self.exit_frame.clone();
                        self.return_label(*number, &frame.slots, 0, &frame);
                    }
                    _ => panic!(
                        "Compiler task/future emission is outside the checked reference domain"
                    ),
                }
            }
            InstructionKind::Copy {
                operand,
                destination,
            } => {
                if !stack(*destination) || destination % 10000 <= needed {
                    self.copy(*operand, *destination, needed);
                }
            }
            InstructionKind::Jump {
                operand,
                arguments,
                poll,
            } => self.jump(*operand, *arguments, *poll, next_label),
            InstructionKind::Apply {
                primitive,
                operands,
                destination,
            } => self.apply(*primitive, &operands.values(), *destination, needed),
            InstructionKind::IfJump {
                test,
                operands,
                true_label,
                false_label,
                poll,
            } => self.ifjump(
                *test,
                &operands.values(),
                *true_label,
                *false_label,
                *poll,
                next_label,
            ),
            InstructionKind::Close(parameters) => self.close(parameters, needed),
        }
    }
}

// ---- Primitive arithmetic and comparisons ----

impl Emitter<'_, '_, '_, '_> {
    fn compare_number(&mut self, number: i64, operand: &Operand68) -> bool {
        if number == BITS_NULL || number == BITS_FALSE {
            self.binary(
                Binary::Compare,
                operand,
                &if number == BITS_NULL { NULL } else { FALSE },
                Width::Long,
            );
            false
        } else if operand.relative_operand() || operand.immediate_operand() {
            if number == 0 {
                self.move_value(operand, &DTEMP, Width::Long);
            } else {
                self.move_operand68(operand, &ATEMP1);
                self.binary(
                    Binary::Compare,
                    &Operand68::immediate(number),
                    &ATEMP1,
                    if (-32768..=32767).contains(&number) {
                        Width::Word
                    } else {
                        Width::Long
                    },
                );
            }
            true
        } else if number == 0 {
            self.move_value(operand, &DTEMP, Width::Long);
            true
        } else if (-128..=127).contains(&number) && !operand.identical(&DTEMP) {
            self.move_quick(number, &DTEMP);
            self.binary(Binary::Compare, operand, &DTEMP, Width::Long);
            false
        } else {
            self.binary(
                Binary::Compare,
                &Operand68::immediate(number),
                operand,
                Width::Long,
            );
            true
        }
    }
    fn compare_machine(&mut self, first: &Operand68, second: &Operand68, size: usize) -> bool {
        self.top_for_operands(first, second, size);
        let order = if first.immediate_operand() {
            let second = self.true_operand(second, size);
            self.compare_number(first.immediate_value(), &second)
        } else if second.immediate_operand() {
            let first = self.true_operand(first, size);
            !self.compare_number(second.immediate_value(), &first)
        } else if first.data_register() || first.address_register() {
            let second = self.true_operand(second, size);
            self.binary(Binary::Compare, &second, first, Width::Long);
            false
        } else if second.data_register() || second.address_register() {
            let first = self.true_operand(first, size);
            self.binary(Binary::Compare, &first, second, Width::Long);
            true
        } else {
            let first = self.true_operand(first, self.machine_needed(second, size));
            self.move_value(&first, &DTEMP, Width::Long);
            let second = self.true_operand(second, size);
            self.binary(Binary::Compare, &second, &DTEMP, Width::Long);
            false
        };
        self.shrink_frame(size);
        order
    }
    fn compare(&mut self, first: usize, second: usize, size: usize) -> bool {
        let first = self.operand68(first, None, self.stack_needed(second, size));
        let second = self.operand68(second, temporary_in(&first).as_ref(), size);
        self.compare_machine(&first, &second, size)
    }
    fn compares(
        &mut self,
        branches: [Branch; 4],
        negate: bool,
        operands: &[usize],
        label: usize,
        size: usize,
    ) {
        if operands.len() <= 1 {
            self.shrink_frame(size);
            if !negate {
                self.branch(Branch::Always, label);
            }
            return;
        }
        if operands.len() == 2 {
            let order = self.compare(operands[0], operands[1], size);
            self.branch(
                branches[if order {
                    if negate { 3 } else { 2 }
                } else if negate {
                    1
                } else {
                    0
                }],
                label,
            );
            return;
        }
        let needed = self.stack_needed(operands[1], self.operands_needed(&operands[2..], size));
        let order = self.compare(operands[0], operands[1], needed);
        let failure = branches[if order { 3 } else { 1 }];
        let success = branches[if order { 2 } else { 0 }];
        if self.frame_size == size as i64 {
            if negate {
                self.branch(failure, label);
                self.compares(branches, negate, &operands[1..], label, size);
            } else {
                let exit = self.fresh_label();
                self.branch(failure, exit);
                self.compares(branches, negate, &operands[1..], label, size);
                self.label(exit);
            }
        } else if negate {
            let next = self.fresh_label();
            self.branch(success, next);
            self.shrink_frame(size);
            self.branch(Branch::Always, label);
            self.label(next);
            self.compares(branches, negate, &operands[1..], label, size);
        } else {
            let next = self.fresh_label();
            let exit = self.fresh_label();
            self.branch(success, next);
            self.shrink_frame(size);
            self.branch(Branch::Always, exit);
            self.label(next);
            self.compares(branches, negate, &operands[1..], label, size);
            self.label(exit);
        }
    }
    fn predicate(
        &mut self,
        primitive: usize,
        negate: bool,
        operands: &[usize],
        label: usize,
        size: usize,
    ) {
        let key = self.generator.catalog.procedures[primitive].key.as_str();
        let branches = match key {
            "##fixnum.<" | "##char<?" => Some([
                Branch::Less,
                Branch::GreaterEqual,
                Branch::Greater,
                Branch::LessEqual,
            ]),
            "##fixnum.>" | "##char>?" => Some([
                Branch::Greater,
                Branch::LessEqual,
                Branch::Less,
                Branch::GreaterEqual,
            ]),
            "##fixnum.<=" | "##char<=?" => Some([
                Branch::LessEqual,
                Branch::Greater,
                Branch::GreaterEqual,
                Branch::Less,
            ]),
            "##fixnum.>=" | "##char>=?" => Some([
                Branch::GreaterEqual,
                Branch::Less,
                Branch::LessEqual,
                Branch::Greater,
            ]),
            "##fixnum.=" | "##eq?" | "##char=?" => Some([
                Branch::Equal,
                Branch::NotEqual,
                Branch::Equal,
                Branch::NotEqual,
            ]),
            _ => None,
        };
        if let Some(branches) = branches {
            self.compares(branches, negate, operands, label, size);
            return;
        }
        let bits = match key {
            "##not" => Some(BITS_FALSE),
            "##null?" => Some(BITS_NULL),
            "##unassigned?" => Some(BITS_UNASSIGNED),
            "##fixnum.zero?" => Some(0),
            _ => None,
        };
        if let Some(bits) = bits {
            let operand = self.operand68(operands[0], None, size);
            self.compare_machine(&operand, &Operand68::immediate(bits), size);
            self.branch(
                if negate {
                    Branch::NotEqual
                } else {
                    Branch::Equal
                },
                label,
            );
            return;
        }
        if key == "##fixnum.odd?" || key == "##fixnum.even?" {
            self.move_to_machine(operands[0], &DTEMP, size);
            self.binary(Binary::And, &Operand68::immediate(8), &DTEMP, Width::Word);
            self.shrink_frame(size);
            self.branch(
                if negate ^ (key == "##fixnum.odd?") {
                    Branch::NotEqual
                } else {
                    Branch::Equal
                },
                label,
            );
            return;
        }
        panic!("unsupported Compiler inline predicate {key}")
    }
    fn ifjump(
        &mut self,
        primitive: usize,
        operands: &[usize],
        yes: usize,
        no: usize,
        poll: bool,
        next: Option<usize>,
    ) {
        let size = self.exit_frame.size;
        self.guarantee_fudge();
        if poll {
            self.poll();
        }
        if next == Some(yes) {
            self.predicate(primitive, true, operands, no, size);
        } else if next == Some(no) {
            self.predicate(primitive, false, operands, yes, size);
        } else {
            self.predicate(primitive, true, operands, no, size);
            self.branch(Branch::Always, yes);
        }
    }
    fn arithmetic_in_place(
        &mut self,
        operands: &[usize],
        destination: &Operand68,
        needed: usize,
        subtract: bool,
    ) {
        for (index, &operand) in operands.iter().enumerate() {
            let remaining = self.operands_needed(&operands[index + 1..], needed);
            let source = self.operand68(
                operand,
                temporary_in(destination).as_ref(),
                self.machine_needed(destination, needed),
            );
            self.top_for_operands(&source, destination, remaining);
            if source.immediate_operand() {
                let destination = self.true_operand(destination, remaining);
                self.add_number(
                    if subtract {
                        -source.immediate_value()
                    } else {
                        source.immediate_value()
                    },
                    &destination,
                );
            } else {
                let value = self.true_operand(&source, remaining);
                if source.data_register()
                    || destination.data_register()
                    || destination.address_register()
                {
                    let destination = self.true_operand(destination, remaining);
                    self.binary(
                        if subtract {
                            Binary::Subtract
                        } else {
                            Binary::Add
                        },
                        &value,
                        &destination,
                        Width::Long,
                    );
                } else {
                    self.move_operand68(&value, &DTEMP);
                    let destination = self.true_operand(destination, remaining);
                    self.binary(
                        if subtract {
                            Binary::Subtract
                        } else {
                            Binary::Add
                        },
                        &DTEMP,
                        &destination,
                        Width::Long,
                    );
                }
            }
        }
    }
    fn add(&mut self, operands: &[usize], location: usize, needed: usize) {
        if operands.is_empty() {
            self.move_to_location(&Operand68::immediate(0), location, needed);
            return;
        }
        if operands.len() == 1 {
            self.copy(operands[0], location, needed);
            return;
        }
        let (mut contained, mut other, mut self_operand) = (vec![], vec![], false);
        if register(location) || stack(location) {
            for &operand in operands {
                if !self_operand && operand == location {
                    self_operand = true;
                } else if self.generator.operands.contains(location, operand) {
                    contained.push(operand);
                } else {
                    other.push(operand);
                }
            }
        } else {
            contained.extend_from_slice(operands);
        }
        let contained_count = contained.len();
        contained.extend(other);
        let all = contained;
        let remaining = self.operands_needed(&all[1..], needed);
        let first_needed = self.stack_needed(all[0], remaining);
        if contained_count <= 1 {
            let destination = self.location68(location, None, first_needed);
            if self_operand {
                self.arithmetic_in_place(&all, &destination, needed, false);
            } else {
                self.move_to_machine(all[0], &destination, remaining);
                self.arithmetic_in_place(&all[1..], &destination, needed, false);
            }
        } else {
            self.move_to_machine(all[0], &DTEMP, self.stack_needed(location, remaining));
            self.arithmetic_in_place(
                &all[1..],
                &DTEMP,
                self.stack_needed(location, needed),
                false,
            );
            if self_operand {
                let destination = self.location68(location, Some(&DTEMP), needed);
                self.top_for_operand(&destination, needed);
                let destination = self.true_operand(&destination, needed);
                self.binary(Binary::Add, &DTEMP, &destination, Width::Long);
            } else {
                self.move_to_location(&DTEMP, location, needed);
            }
        }
    }
    fn subtract(&mut self, operands: &[usize], location: usize, needed: usize) {
        if operands.len() == 1 {
            if (register(location) || stack(location)) && location != 0 {
                self.copy(operands[0], location, self.stack_needed(location, needed));
                let destination = self.location68(location, None, needed);
                self.top_for_operand(&destination, needed);
                let destination = self.true_operand(&destination, needed);
                self.negate(&destination);
            } else {
                self.move_to_machine(operands[0], &DTEMP, self.stack_needed(location, needed));
                self.negate(&DTEMP);
                self.move_to_location(&DTEMP, location, needed);
            }
            return;
        }
        let remaining = self.operands_needed(&operands[1..], needed);
        let first_needed = self.stack_needed(operands[0], remaining);
        if (register(location) || stack(location))
            && !operands[1..]
                .iter()
                .any(|&o| self.generator.operands.contains(location, o))
        {
            let destination = self.location68(location, None, first_needed);
            if operands[0] != location {
                self.move_to_machine(operands[0], &destination, remaining);
            }
            self.arithmetic_in_place(&operands[1..], &destination, needed, true);
        } else {
            self.move_to_machine(operands[0], &DTEMP, self.stack_needed(location, remaining));
            self.arithmetic_in_place(
                &operands[1..],
                &DTEMP,
                self.stack_needed(location, needed),
                true,
            );
            self.move_to_location(&DTEMP, location, needed);
        }
    }
}

// ---- Fixnum multiplication retains the source shift/68020 choices ----

impl Emitter<'_, '_, '_, '_> {
    fn multiply_machine(&mut self, operand: &Operand68, destination: &Operand68) {
        self.asm.part(Part::M68020);
        self.asm.word(19456 + operand.mode_register());
        self.asm.word(2048 + destination.encoded() * 4096);
        self.extension(operand, false, Width::Long);
        self.instruction_text("mulsl", &[operand.clone(), destination.clone()]);
    }
    fn multiply_number(&mut self, number: i64, destination: &Operand68) {
        if number == 0 {
            self.move_quick(0, destination);
            return;
        }
        let absolute = number.unsigned_abs();
        if absolute != 1 {
            if absolute.is_power_of_two() {
                let shift = absolute.trailing_zeros().min(32);
                if shift <= 8 || destination.identical(&DTEMP) {
                    let mut remaining = shift;
                    while remaining != 0 {
                        let step = remaining.min(8);
                        self.shift(
                            &Operand68::immediate(step as i64),
                            destination,
                            false,
                            false,
                        );
                        remaining -= step;
                    }
                } else {
                    self.move_quick(shift as i64, &DTEMP);
                    self.shift(&DTEMP, destination, false, false);
                }
            } else {
                self.multiply_machine(&Operand68::immediate(number), destination);
                return;
            }
        }
        if number < 0 {
            self.negate(destination);
        }
    }
    fn multiply_in_place(&mut self, operands: &[usize], destination: &Operand68, needed: usize) {
        for (index, &operand) in operands.iter().enumerate() {
            let remaining = self.operands_needed(&operands[index + 1..], needed);
            let source = self.operand68(operand, temporary_in(destination).as_ref(), needed);
            self.top_for_operand(&source, remaining);
            if source.immediate_operand() {
                self.multiply_number(source.immediate_value().div_euclid(8), destination);
            } else {
                self.shift(&Operand68::immediate(3), destination, true, false);
                let source = self.true_operand(&source, remaining);
                self.multiply_machine(&source, destination);
            }
        }
    }
    fn multiply(&mut self, operands: &[usize], location: usize, needed: usize) {
        if operands.is_empty() {
            self.move_to_location(&Operand68::immediate(8), location, needed);
            return;
        }
        if operands.len() == 1 {
            self.copy(operands[0], location, needed);
            return;
        }
        let (mut contained, mut other, mut self_operand) = (vec![], vec![], false);
        if register(location) && location != 0 {
            for &operand in operands {
                if !self_operand && operand == location {
                    self_operand = true;
                } else if self.generator.operands.contains(location, operand) {
                    contained.push(operand);
                } else {
                    other.push(operand);
                }
            }
        } else {
            contained.extend_from_slice(operands);
        }
        let contained_count = contained.len();
        contained.extend(other);
        let all = contained;
        let remaining = self.operands_needed(&all[1..], needed);
        let first_needed = self.stack_needed(all[0], remaining);
        if contained_count == 0 {
            let destination = self.location68(location, None, first_needed);
            if self_operand {
                self.multiply_in_place(&all, &destination, needed);
            } else {
                self.move_to_machine(all[0], &destination, remaining);
                self.multiply_in_place(&all[1..], &destination, needed);
            }
        } else {
            self.move_to_machine(all[0], &DTEMP, self.stack_needed(location, remaining));
            self.multiply_in_place(&all[1..], &DTEMP, self.stack_needed(location, needed));
            if self_operand {
                let destination = self.location68(location, Some(&DTEMP), needed);
                self.top_for_operand(&destination, needed);
                self.shift(&Operand68::immediate(3), &DTEMP, true, false);
                let destination = self.true_operand(&destination, needed);
                self.multiply_machine(&DTEMP, &destination);
            } else {
                self.move_to_location(&DTEMP, location, needed);
            }
        }
    }
}

// ---- Vector access, mutation and closure layout ----

impl Emitter<'_, '_, '_, '_> {
    fn result_register(&self, location: usize) -> Operand68 {
        if register(location) && location != 0 {
            register68(location)
        } else {
            DTEMP
        }
    }
    fn vector_length(&mut self, operand: usize, location: usize, needed: usize) {
        let register = self.result_register(location);
        self.move_to_machine(operand, &ATEMP1, self.stack_needed(location, needed));
        self.move_operand68(&Operand68::displacement(9, -3), &register);
        self.shift(&Operand68::immediate(7), &register, true, true);
        self.move_to_location(&register, location, needed);
    }
    fn vector_reference(&mut self, operands: &[usize], location: usize, needed: usize) {
        let needed_location = self.stack_needed(location, needed);
        let register = self.result_register(location);
        let second = self.operand68(
            operands[1],
            None,
            self.stack_needed(operands[0], needed_location),
        );
        let first = self.operand68(operands[0], temporary_in(&second).as_ref(), needed_location);
        self.top_for_operands(&first, &second, needed_location);
        let address = if second.immediate_operand() {
            let value = self.true_operand(&first, needed_location);
            self.move_operand68(&value, &ATEMP1);
            Operand68::displacement_or_indirect(9, second.immediate_value().div_euclid(2) + 1)
        } else {
            let index = self.true_operand(&second, self.machine_needed(&first, needed_location));
            self.move_operand68(&index, &DTEMP);
            self.shift(&Operand68::immediate(1), &DTEMP, true, false);
            let value = self.true_operand(&first, needed_location);
            self.move_operand68(&value, &ATEMP1);
            Operand68::indexed(9, 0, 1)
        };
        self.move_value(&address, &register, Width::Long);
        self.move_to_location(&register, location, needed);
    }
    fn vector_set(&mut self, operands: &[usize], location: Option<usize>, needed: usize) {
        let needed_location = location
            .map(|l| self.stack_needed(l, needed))
            .unwrap_or(needed);
        let needed_location = if location.is_some_and(|l| l != operands[0]) {
            self.stack_needed(operands[0], needed_location)
        } else {
            needed
        };
        let needed_third = self.stack_needed(operands[2], needed_location);
        let second = self.operand68(
            operands[1],
            None,
            self.stack_needed(operands[0], needed_third),
        );
        let first = self.operand68(operands[0], temporary_in(&second).as_ref(), needed_third);
        self.top_for_operands(&first, &second, needed_third);
        let destination = if second.immediate_operand() {
            let value = self.true_operand(&first, needed_third);
            self.move_operand68(&value, &ATEMP1);
            Operand68::displacement_or_indirect(9, second.immediate_value().div_euclid(2) + 1)
        } else {
            // The source uses sn-loc here, even while the third value remains.
            let index = self.true_operand(&second, self.machine_needed(&first, needed_location));
            self.move_operand68(&index, &DTEMP);
            self.shift(&Operand68::immediate(1), &DTEMP, true, false);
            let value = self.true_operand(&first, needed_location);
            self.move_operand68(&value, &ATEMP1);
            Operand68::indexed(9, 0, 1)
        };
        self.move_to_machine(operands[2], &destination, needed_location);
        if let Some(location) = location.filter(|&l| l != operands[0]) {
            self.copy(operands[0], location, needed);
        }
    }
    fn vector(&mut self, operands: &[usize], location: Option<usize>, needed: usize) {
        let needed_location = location
            .map(|l| self.stack_needed(l, needed))
            .unwrap_or(needed);
        let bytes = 4 + operands.len() * 4;
        let adjust = (8 - bytes % 8) % 8;
        self.guarantee_space(bytes.div_ceil(8) * 2);
        if adjust != 0 {
            self.quick(adjust as i64, &HEAP, true, Width::Long);
        }
        for index in (0..operands.len()).rev() {
            self.move_to_machine(
                operands[index],
                &Operand68::predecrement(11),
                self.operands_needed(&operands[..index], needed_location),
            );
        }
        self.move_value(
            &Operand68::immediate((bytes - 4) as i64 * 256),
            &Operand68::predecrement(11),
            Width::Long,
        );
        if let Some(location) = location {
            self.lea(&Operand68::displacement(11, 3), &ATEMP2);
            self.move_to_location(&ATEMP2, location, needed);
        }
    }
    fn pair_reference(
        &mut self,
        operand: usize,
        location: usize,
        needed: usize,
        mut pattern: usize,
    ) {
        self.move_to_machine(operand, &ATEMP1, self.stack_needed(location, needed));
        while pattern > 3 {
            self.move_value(
                &if pattern % 2 == 1 {
                    Operand68::predecrement(9)
                } else {
                    Operand68::indirect(9)
                },
                &ATEMP1,
                Width::Long,
            );
            pattern /= 2;
        }
        self.move_to_location(
            &if pattern == 3 {
                Operand68::predecrement(9)
            } else {
                Operand68::indirect(9)
            },
            location,
            needed,
        );
    }
    fn pair_set(&mut self, operands: &[usize], location: Option<usize>, needed: usize, cdr: bool) {
        let needed_location = location
            .map(|l| self.stack_needed(l, needed))
            .unwrap_or(needed);
        self.move_to_machine(
            operands[0],
            &ATEMP1,
            self.stack_needed(operands[1], needed_location),
        );
        let keep_pair = location.is_some_and(|l| l != operands[0]);
        let field = if cdr {
            if keep_pair {
                Operand68::displacement(9, -4)
            } else {
                Operand68::predecrement(9)
            }
        } else {
            Operand68::indirect(9)
        };
        self.move_to_machine(operands[1], &field, needed_location);
        if let Some(location) = location.filter(|_| keep_pair) {
            self.move_to_location(&ATEMP1, location, needed);
        }
    }
    fn cell(&mut self, operand: usize, location: usize, needed: usize) {
        self.guarantee_space(2);
        self.move_to_machine(
            operand,
            &Operand68::predecrement(11),
            self.stack_needed(location, needed),
        );
        self.move_to_location(&HEAP, location, needed);
        // Synthetic immediate helper arguments have no escaping identity. This
        // typed port emits them directly; original helpers intern a GVM operand.
        self.move_number(BITS_NULL, &Operand68::predecrement(11));
    }
    fn cons(&mut self, operands: &[usize], location: usize, needed: usize) {
        let needed_location = self.stack_needed(location, needed);
        self.guarantee_space(2);
        if self.generator.operands.contains(location, operands[1]) {
            self.move_to_machine(
                operands[0],
                &Operand68::predecrement(11),
                self.stack_needed(operands[1], needed_location),
            );
            self.move_operand68(&HEAP, &ATEMP2);
            self.move_to_machine(operands[1], &Operand68::predecrement(11), needed_location);
            self.move_to_location(&ATEMP2, location, needed);
        } else {
            let after = self.stack_needed(operands[1], needed);
            self.move_to_machine(
                operands[0],
                &Operand68::predecrement(11),
                self.stack_needed(location, after),
            );
            self.move_to_location(&HEAP, location, after);
            self.move_to_machine(operands[1], &Operand68::predecrement(11), needed);
        }
    }
    fn close(&mut self, parameters: &[Box<ClosureParameters>], needed: usize) {
        fn bytes(size: usize) -> usize {
            ((size + 2) * 4).div_ceil(16) * 16
        }
        let total: usize = parameters
            .iter()
            .map(|p| bytes(p.operands.values().len()))
            .sum();
        let label = self.fresh_label();
        self.move_value(&Operand68::displacement(13, 72), &ATEMP2, Width::Long);
        self.move_number(total as i64, &DTEMP);
        self.binary(Binary::Subtract, &DTEMP, &ATEMP2, Width::Long);
        self.binary(
            Binary::Compare,
            &Operand68::displacement(13, 68),
            &ATEMP2,
            Width::Long,
        );
        self.branch(Branch::CarryClear, label);
        self.trap_return(self.entry_frame.clone(), false, None, 15, label);
        self.move_value(&ATEMP2, &Operand68::displacement(13, 72), Width::Long);
        let all: Vec<_> = parameters
            .iter()
            .flat_map(|p| p.operands.values())
            .collect();
        let needed_all = self.operands_needed(&all, needed);
        for (index, parameter) in parameters.iter().enumerate() {
            let size = parameter.operands.values().len();
            if size == 1 {
                self.quick(2, &ATEMP2, false, Width::Long);
            } else {
                self.move_value(
                    &Operand68::immediate(32768 + (size + 1) as i64 * 4),
                    &Operand68::postincrement(10),
                    Width::Word,
                );
            }
            let rest: Vec<_> = parameters[index + 1..]
                .iter()
                .map(|p| p.destination)
                .collect();
            self.move_to_location(
                &ATEMP2,
                parameter.destination,
                self.operands_needed(&rest, needed_all),
            );
            self.add_number(
                if index + 1 == parameters.len() {
                    bytes(size) as i64 - total as i64 + 2
                } else {
                    bytes(size) as i64 - 2
                },
                &ATEMP2,
            );
        }
        for (index, parameter) in parameters.iter().enumerate() {
            let operands = parameter.operands.values();
            self.lea(&Operand68::relative(parameter.label, 0), &ATEMP1);
            self.move_value(&ATEMP1, &Operand68::postincrement(10), Width::Long);
            let rest: Vec<_> = parameters[index + 1..]
                .iter()
                .flat_map(|p| p.operands.values())
                .collect();
            let needed_rest = self.operands_needed(&rest, needed);
            for (i, &operand) in operands.iter().enumerate() {
                self.move_to_machine(
                    operand,
                    &Operand68::postincrement(10),
                    self.operands_needed(&operands[i + 1..], needed_rest),
                );
            }
            if index + 1 < parameters.len() {
                self.add_number(
                    bytes(operands.len()) as i64 - (operands.len() + 1) as i64 * 4,
                    &ATEMP2,
                );
            }
        }
    }
    fn apply(
        &mut self,
        primitive: usize,
        operands: &[usize],
        location: Option<usize>,
        needed: usize,
    ) {
        let description = &self.generator.catalog.procedures[primitive];
        let inline_effects = description.inline_effects.expect("inline generator");
        if !inline_effects && location.is_none_or(|l| stack(l) && l % 10000 > needed) {
            return;
        }
        let key = description.key.as_str();
        if description.test {
            let location = location.expect("predicate result location");
            let yes = self.fresh_label();
            let continuation = self.fresh_label();
            let register = self.result_register(location);
            self.predicate(primitive, false, operands, yes, self.frame_size as usize);
            self.move_number(BITS_FALSE, &register);
            self.branch(Branch::Always, continuation);
            self.label(yes);
            self.move_number(BITS_TRUE, &register);
            self.label(continuation);
            self.move_to_location(&register, location, needed);
            return;
        }
        match key {
            "##fixnum.+" => self.add(operands, location.unwrap(), needed),
            "##fixnum.-" => self.subtract(operands, location.unwrap(), needed),
            "##fixnum.*" => self.multiply(operands, location.unwrap(), needed),
            "##vector-length" => self.vector_length(operands[0], location.unwrap(), needed),
            "##vector-ref" => self.vector_reference(operands, location.unwrap(), needed),
            "##vector-set!" => self.vector_set(operands, location, needed),
            "##vector" => self.vector(operands, location, needed),
            "##cons" => self.cons(operands, location.unwrap(), needed),
            "##make-cell" => self.cell(operands[0], location.unwrap(), needed),
            "##cell-ref" => self.pair_reference(operands[0], location.unwrap(), needed, 2),
            "##set-car!" | "##cell-set!" => self.pair_set(operands, location, needed, false),
            "##set-cdr!" => self.pair_set(operands, location, needed, true),
            name if pair_pattern(name).is_some() => self.pair_reference(
                operands[0],
                location.unwrap(),
                needed,
                pair_pattern(name).unwrap(),
            ),
            _ => panic!("unsupported Compiler inline generator {key}"),
        }
    }
}
fn pair_pattern(name: &str) -> Option<usize> {
    let inner = name.strip_prefix("##c")?.strip_suffix('r')?;
    if inner.is_empty() || inner.len() > 4 || !inner.bytes().all(|b| b == b'a' || b == b'd') {
        return None;
    }
    Some(inner.bytes().fold(1, |pattern, letter| {
        pattern * 2 + usize::from(letter == b'd')
    }))
}

// ---- Object traversal and genuine per-procedure emission ----

pub(super) fn program(generator: &Generator<'_, '_>, root: Object, word_audit: bool) -> ObjectFile {
    let mut output = ObjectFile::new(word_audit);
    let mut objects = ObjectQueue::new();
    output.word(5);
    output.word(0);
    objects.add(root, generator);
    while let Some(object) = objects.pending.pop_front() {
        output.line("|------------------------------------------------------".to_owned());
        match object {
            Object::Procedure(procedure) => {
                let procedure = &generator.procedures[procedure];
                let group = procedure.blocks.expect("compiled procedure");
                if procedure.primitive {
                    output.long(1);
                    output.symbol_word(0, &procedure.name);
                    output.line(format!("| #[primitive {}] =", procedure.name));
                } else {
                    output.long(2);
                }
                let mut emitter = Emitter::new(generator, group, &mut objects);
                let code = generator.code_list(group);
                for (index, instruction) in code.iter().enumerate() {
                    emitter.asm.gvm_comment(index);
                    emitter.instruction(
                        index.checked_sub(1).map(|i| code[i].instruction),
                        instruction.instruction,
                        code.get(index + 1).map(|c| c.instruction),
                        instruction.slots_needed,
                    );
                }
                emitter.asm.assemble(
                    &mut output,
                    generator,
                    emitter.objects,
                    Object::Literal(Rc::new(atom("#f"))),
                );
                // Debug output is disabled in the source benchmark, but descriptor
                // construction and label-position mutation remain real work.
                std::hint::black_box((&emitter.variables, &emitter.labels));
            }
            Object::Literal(_) => {
                panic!("Compiler compound object dumping is outside the checked reference domain")
            }
            Object::Primitive(_) => unreachable!(),
        }
    }
    output.line(String::new());
    output
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn trap_slot_adjustment_always_copies_the_surviving_spine() {
        let slots = Ids::from_slice(&[3, 2, 1]);
        for (delta, expected) in [
            (-1, vec![2, 1]),
            (0, vec![3, 2, 1]),
            (2, vec![0, 0, 3, 2, 1]),
        ] {
            let copy = trap_frame_slots(&slots, delta, 0);
            assert_eq!(copy.values(), expected);
            let old = ids_suffix(&slots, if delta < 0 { -delta as usize } else { 0 });
            let new = ids_suffix(&copy, delta.max(0) as usize);
            assert!(!Rc::ptr_eq(
                old.0.as_ref().unwrap(),
                new.0.as_ref().unwrap()
            ));
        }
        assert_eq!(slots.values(), vec![3, 2, 1]);
    }
    #[test]
    fn composed_pair_access_and_argument_flags_match_source_recipes() {
        assert_eq!(pair_pattern("##car"), Some(2));
        assert_eq!(pair_pattern("##cdr"), Some(3));
        assert_eq!(pair_pattern("##cadr"), Some(5));
        assert_eq!(pair_pattern("##cdddar"), Some(30));
        assert_eq!(pair_pattern("##cell-ref"), None);
        assert_eq!(
            (
                argument_count(0),
                argument_count(1),
                argument_count(2),
                argument_count(5)
            ),
            (1, -1, 0, 6)
        );
    }
    #[test]
    fn register_abi_and_temp_selection_are_concrete() {
        assert!(register68(0).identical(&Operand68::address(0)));
        assert!(register68(3).identical(&Operand68::data(3)));
        assert!(pick_address(Some(&ATEMP1)).identical(&ATEMP2));
        assert!(
            temporary_in(&Operand68::indexed(9, 0, 1))
                .unwrap()
                .identical(&DTEMP)
        );
    }
}
