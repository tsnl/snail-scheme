use super::*;

// ---- Frames and block boundaries ----

impl Generator<'_, '_> {
    fn entry_size(&self, block: usize) -> usize {
        self.instructions[self.blocks[block].label].frame.size
    }
    fn exit_size(&self, block: usize) -> usize {
        self.instructions[self.blocks[block].branch.unwrap()]
            .frame
            .size
    }
    fn slots_gained(&self, block: usize) -> isize {
        self.exit_size(block) as isize - self.entry_size(block) as isize
    }
    fn empty_block(&self, block: usize) -> bool {
        matches!(
            self.instructions[self.blocks[block].label].kind,
            InstructionKind::Label {
                kind: LabelKind::Simple,
                ..
            }
        ) && self.blocks[block].instructions.is_empty()
    }
    fn last_non_branch(&self, block: usize) -> usize {
        self.blocks[block]
            .instructions
            .back()
            .copied()
            .unwrap_or(self.blocks[block].label)
    }
    fn truncate_frame(&self, frame: &Frame, size: usize) -> Rc<Frame> {
        Rc::new(Frame {
            size,
            slots: ids_suffix(&frame.slots, frame.size.saturating_sub(size)),
            registers: frame.registers.clone(),
            closed: frame.closed.clone(),
            live: frame.live.clone(),
        })
    }
    fn direct_jump(&self, instruction: usize) -> Option<usize> {
        match self.instructions[instruction].kind {
            InstructionKind::Jump {
                operand,
                arguments: None,
                ..
            } if operand / 10_000 == 2 => Some(operand % 10_000),
            _ => None,
        }
    }
}

// ---- Jump cascades with frame and polling adjustments ----

impl Generator<'_, '_> {
    fn equivalent_label(&self, number: usize, seen: &Ids) -> usize {
        if seen.has(number) {
            return number;
        }
        let block = self.label_block(number);
        let branch = self.blocks[block].branch.unwrap();
        if self.empty_block(block) && self.slots_gained(block) == 0 {
            if let Some(target) = self.direct_jump(branch) {
                if matches!(
                    self.instructions[branch].kind,
                    InstructionKind::Jump { poll: false, .. }
                ) {
                    return self.equivalent_label(target, &Ids::cons(number, seen.clone()));
                }
            }
        }
        number
    }
    fn cascade_target(
        &self,
        number: usize,
        size: isize,
        poll: bool,
        seen: &Ids,
    ) -> (usize, isize, bool) {
        if seen.has(number) {
            return (number, size, poll);
        }
        let block = self.label_block(number);
        if self.empty_block(block) && self.slots_gained(block) <= 0 {
            let branch = self.blocks[block].branch.unwrap();
            if let Some(target) = self.direct_jump(branch) {
                let InstructionKind::Jump {
                    poll: next_poll, ..
                } = self.instructions[branch].kind
                else {
                    unreachable!()
                };
                return self.cascade_target(
                    target,
                    size + self.slots_gained(block),
                    poll || next_poll,
                    &Ids::cons(number, seen.clone()),
                );
            }
        }
        (number, size, poll)
    }
    fn adjusted_operand(&mut self, operand: usize, adjustment: isize) -> usize {
        if stack(operand) {
            let number = operand as isize % 10_000 + adjustment;
            assert!(number >= 0);
            return stack_slot(number as usize);
        }
        if let Some((base, index)) = self.operands.entry_if_closure(operand) {
            let base = self.adjusted_operand(base, adjustment);
            return self.operands.closure(base, index);
        }
        operand
    }
    fn remove_jump_cascades(&mut self) {
        let blocks: Vec<_> = self.groups[self.current_group]
            .blocks
            .iter()
            .copied()
            .collect();
        for block in blocks {
            let old = self.blocks[block].branch.unwrap();
            let frame = self.instructions[old].frame.clone();
            let source = self.instructions[old].source;
            match self.instructions[old].kind.clone() {
                InstructionKind::IfJump {
                    test,
                    operands,
                    true_label,
                    false_label,
                    poll,
                } => {
                    let kind = InstructionKind::IfJump {
                        test,
                        operands,
                        true_label: self.equivalent_label(true_label, &Ids::default()),
                        false_label: self.equivalent_label(false_label, &Ids::default()),
                        poll,
                    };
                    let new = self.instruction(kind, frame, source);
                    self.blocks[block].branch = Some(new);
                }
                InstructionKind::Jump {
                    operand,
                    arguments: None,
                    poll,
                } if operand / 10_000 == 2 => {
                    let (target, size, poll) = self.cascade_target(
                        operand % 10_000,
                        frame.size as isize,
                        poll,
                        &Ids::default(),
                    );
                    assert!(size >= 0);
                    let destination = self.label_block(target);
                    let new = if self.empty_block(destination) {
                        let last = self.blocks[destination].branch.unwrap();
                        let new_size = size + self.slots_gained(destination);
                        assert!(new_size >= 0);
                        let new_frame = self.truncate_frame(&frame, new_size as usize);
                        let adjustment = size - self.entry_size(destination) as isize;
                        let kind = match self.instructions[last].kind.clone() {
                            InstructionKind::IfJump {
                                test,
                                operands,
                                true_label,
                                false_label,
                                poll: last_poll,
                            } => {
                                let operands: Vec<_> = operands
                                    .values()
                                    .into_iter()
                                    .map(|operand| self.adjusted_operand(operand, adjustment))
                                    .collect();
                                InstructionKind::IfJump {
                                    test,
                                    operands: Ids::from_slice(&operands),
                                    true_label: self.equivalent_label(true_label, &Ids::default()),
                                    false_label: self
                                        .equivalent_label(false_label, &Ids::default()),
                                    poll: poll || last_poll,
                                }
                            }
                            InstructionKind::Jump {
                                operand,
                                arguments,
                                poll: last_poll,
                            } => InstructionKind::Jump {
                                operand: self.adjusted_operand(operand, adjustment),
                                arguments,
                                poll: poll || last_poll,
                            },
                            _ => unreachable!(),
                        };
                        self.instruction(kind, new_frame, self.instructions[last].source)
                    } else {
                        let frame = self.truncate_frame(&frame, size as usize);
                        self.instruction(
                            InstructionKind::Jump {
                                operand: label(target),
                                arguments: None,
                                poll,
                            },
                            frame,
                            source,
                        )
                    };
                    self.blocks[block].branch = Some(new);
                }
                InstructionKind::Jump { .. } => (),
                _ => unreachable!(),
            }
        }
    }
}

// ---- Reachability, references and direct predecessors ----

struct Reachability {
    reached: VecDeque<usize>,
    pending: VecDeque<usize>,
}
impl Reachability {
    fn reach(&mut self, generator: &mut Generator<'_, '_>, block: usize, from: Option<usize>) {
        if let Some(from) = from {
            generator.blocks[from].references = generator.blocks[from].references.adjoin(block);
        }
        if !self.reached.contains(&block) {
            generator.blocks[block].references = Ids::default();
            generator.blocks[block].precedents = Ids::default();
            self.reached.push_back(block);
            self.pending.push_back(block);
        }
    }
    fn operand(&mut self, generator: &mut Generator<'_, '_>, operand: usize, from: usize) {
        if operand / 10_000 == 2 {
            let block = generator.label_block(operand % 10_000);
            self.reach(generator, block, Some(from));
        } else if let Some((base, _)) = generator.operands.entry_if_closure(operand) {
            self.operand(generator, base, from);
        }
    }
    fn direct(&mut self, generator: &mut Generator<'_, '_>, number: usize, from: usize) {
        let block = generator.label_block(number);
        self.reach(generator, block, Some(from));
        generator.blocks[block].precedents = generator.blocks[block].precedents.adjoin(from);
    }
    fn instruction(&mut self, generator: &mut Generator<'_, '_>, instruction: usize, block: usize) {
        match generator.instructions[instruction].kind.clone() {
            InstructionKind::Label { .. } => (),
            InstructionKind::Apply {
                operands,
                destination,
                ..
            } => {
                for operand in operands.values() {
                    self.operand(generator, operand, block);
                }
                if let Some(operand) = destination {
                    self.operand(generator, operand, block);
                }
            }
            InstructionKind::Copy {
                operand,
                destination,
            } => {
                self.operand(generator, operand, block);
                self.operand(generator, destination, block);
            }
            InstructionKind::Close(parameters) => {
                for parameters in parameters {
                    let target = generator.label_block(parameters.label);
                    self.reach(generator, target, Some(block));
                    self.operand(generator, parameters.destination, block);
                    for operand in parameters.operands.values() {
                        self.operand(generator, operand, block);
                    }
                }
            }
            InstructionKind::IfJump {
                operands,
                true_label,
                false_label,
                ..
            } => {
                for operand in operands.values() {
                    self.operand(generator, operand, block);
                }
                self.direct(generator, true_label, block);
                self.direct(generator, false_label, block);
            }
            InstructionKind::Jump { operand, .. } => {
                if operand / 10_000 == 2 {
                    self.direct(generator, operand % 10_000, block);
                } else {
                    self.operand(generator, operand, block);
                }
            }
        }
    }
}
impl Generator<'_, '_> {
    fn remove_dead_blocks(&mut self) {
        let mut scan = Reachability {
            reached: VecDeque::new(),
            pending: VecDeque::new(),
        };
        let entry = self.label_block(self.groups[self.current_group].entry);
        scan.reach(self, entry, None);
        while let Some(block) = scan.pending.pop_front() {
            scan.instruction(self, self.blocks[block].label, block);
            let instructions: Vec<_> = self.blocks[block].instructions.iter().copied().collect();
            for instruction in instructions {
                scan.instruction(self, instruction, block);
            }
            scan.instruction(self, self.blocks[block].branch.unwrap(), block);
        }
        self.groups[self.current_group].blocks = scan.reached;
    }
    fn remove_useless_jumps(&mut self) -> bool {
        let mut changed = false;
        let blocks: Vec<_> = self.groups[self.current_group]
            .blocks
            .iter()
            .copied()
            .collect();
        for block in blocks {
            loop {
                let branch = self.blocks[block].branch.unwrap();
                if !matches!(
                    self.instructions[branch].kind,
                    InstructionKind::Jump { poll: false, .. }
                ) {
                    break;
                }
                let Some(target) = self.direct_jump(branch) else {
                    break;
                };
                let target = self.label_block(target);
                let last = self.last_non_branch(block);
                let simple = matches!(
                    self.instructions[self.blocks[target].label].kind,
                    InstructionKind::Label {
                        kind: LabelKind::Simple,
                        ..
                    }
                );
                if !simple
                    || self.instructions[last].frame.size != self.entry_size(target)
                    || self.blocks[target].precedents.values().len() != 1
                {
                    break;
                }
                changed = true;
                let tail = self.blocks[target].instructions.clone();
                self.blocks[block].instructions.extend(tail);
                self.blocks[block].branch = self.blocks[target].branch;
            }
        }
        changed
    }
}

// ---- Backward stack-slot requirements ----

impl Generator<'_, '_> {
    fn operand_slots(&self, operand: usize, needed: usize) -> usize {
        if stack(operand) {
            return needed.max(operand % 10_000);
        }
        if let Some((base, _)) = self.operands.entry_if_closure(operand) {
            return self.operand_slots(base, needed);
        }
        needed
    }
    fn destination_slots(&self, destination: Option<usize>, mut needed: usize) -> usize {
        if let Some(destination) = destination {
            if stack(destination) && destination % 10_000 >= needed {
                needed = destination % 10_000 - 1;
            }
            if let Some((base, _)) = self.operands.entry_if_closure(destination) {
                needed = self.operand_slots(base, needed);
            }
        }
        needed
    }
    fn operands_slots(&self, operands: &Ids, needed: usize) -> usize {
        operands
            .values()
            .into_iter()
            .rev()
            .fold(needed, |needed, operand| {
                self.operand_slots(operand, needed)
            })
    }
    fn instruction_slots(&self, instruction: usize, needed: usize) -> usize {
        match &self.instructions[instruction].kind {
            InstructionKind::Label { .. } => needed,
            InstructionKind::Apply {
                operands,
                destination,
                ..
            } => self.operands_slots(operands, self.destination_slots(*destination, needed)),
            InstructionKind::Copy {
                operand,
                destination,
            } => self.operand_slots(*operand, self.destination_slots(Some(*destination), needed)),
            InstructionKind::Close(parameters) => {
                let mut needed = needed;
                for parameters in parameters.iter().rev() {
                    needed = self.operands_slots(&parameters.operands, needed);
                }
                for parameters in parameters.iter().rev() {
                    needed = self.destination_slots(Some(parameters.destination), needed);
                }
                needed
            }
            InstructionKind::IfJump { operands, .. } => self.operands_slots(operands, needed),
            InstructionKind::Jump { operand, .. } => self.operand_slots(*operand, needed),
        }
    }
    fn tail_slots(&self, tail: &[usize], branch: usize) -> usize {
        let needed = self.instruction_slots(branch, self.instructions[branch].frame.size);
        tail.iter().rev().fold(needed, |needed, &instruction| {
            self.instruction_slots(instruction, needed)
        })
    }
}

// ---- Hashed whole-block and common-tail merging ----

struct CommonBlocks<'g, 's, 'a> {
    generator: &'g mut Generator<'s, 'a>,
    table: Vec<Ids>,
    primitives: Ids,
    replacements: Bindings,
    changed: bool,
}
impl CommonBlocks<'_, '_, '_> {
    fn replacement(&self, number: usize) -> usize {
        self.replacements
            .get(number)
            .map(|pair| pair.value.get())
            .unwrap_or(number)
    }
    fn primitive_hash(&mut self, primitive: usize) -> usize {
        let n = self.primitives.values().len();
        if let Some(i) = ids_position(&self.primitives, primitive) {
            return n - i;
        }
        self.primitives = Ids::cons(primitive, self.primitives.clone());
        n + 1
    }
    fn operands_hash(&self, operands: &Ids) -> usize {
        let mut n = 0;
        for operand in operands.values() {
            if operand / 10_000 != 2 {
                n = (n * 10_000 + operand) % self.table.len();
            }
        }
        n
    }
    fn block_hash(&mut self, block: usize) -> usize {
        let branch = self.generator.blocks[block].branch.unwrap();
        let frame = self.generator.instructions[branch].frame.size;
        let hash = match self.generator.instructions[branch].kind.clone() {
            InstructionKind::IfJump { test, operands, .. } => {
                self.operands_hash(&operands) as isize
                    + 10 * self.primitive_hash(test) as isize
                    + 100 * frame as isize
            }
            InstructionKind::Jump {
                operand, arguments, ..
            } => {
                self.operands_hash(&Ids::from_slice(&[operand])) as isize
                    + 10 * arguments.map(|n| n as isize).unwrap_or(-1)
                    + 100 * frame as isize
            }
            _ => 0,
        };
        hash.rem_euclid(self.table.len() as isize) as usize
    }
    fn operand_equal(&self, first: Option<usize>, second: Option<usize>) -> bool {
        let (Some(first), Some(second)) = (first, second) else {
            return first == second;
        };
        if first / 10_000 == 2 {
            return second / 10_000 == 2
                && self.replacement(first % 10_000) == self.replacement(second % 10_000);
        }
        if let Some((base, index)) = self.generator.operands.entry_if_closure(first) {
            return self
                .generator
                .operands
                .entry_if_closure(second)
                .is_some_and(|(other, other_index)| {
                    index == other_index && self.operand_equal(Some(base), Some(other))
                });
        }
        first == second
    }
    fn operands_equal(&self, first: &Ids, second: &Ids) -> bool {
        match (&first.0, &second.0) {
            (None, None) => true,
            (Some(a), Some(b)) => {
                self.operand_equal(Some(a.id), Some(b.id)) && self.operands_equal(&a.next, &b.next)
            }
            _ => false,
        }
    }
    fn instruction_equal(&self, first: usize, second: usize) -> bool {
        let first = &self.generator.instructions[first];
        let second = &self.generator.instructions[second];
        // The original merger deliberately compares frame size alone. Full
        // frame/alias equality is an independent diagnostic, not this predicate.
        if first.frame.size != second.frame.size {
            return false;
        }
        match (&first.kind, &second.kind) {
            (InstructionKind::Label { kind: a, .. }, InstructionKind::Label { kind: b, .. }) => {
                a == b
            }
            (
                InstructionKind::Apply {
                    primitive: a,
                    operands: args_a,
                    destination: loc_a,
                },
                InstructionKind::Apply {
                    primitive: b,
                    operands: args_b,
                    destination: loc_b,
                },
            ) => {
                a == b && self.operands_equal(args_a, args_b) && self.operand_equal(*loc_a, *loc_b)
            }
            (
                InstructionKind::Copy {
                    operand: a,
                    destination: loc_a,
                },
                InstructionKind::Copy {
                    operand: b,
                    destination: loc_b,
                },
            ) => {
                self.operand_equal(Some(*a), Some(*b))
                    && self.operand_equal(Some(*loc_a), Some(*loc_b))
            }
            (InstructionKind::Close(a), InstructionKind::Close(b)) => {
                a.len() == b.len()
                    && a.iter().zip(b).all(|(a, b)| {
                        self.operand_equal(Some(a.destination), Some(b.destination))
                            && self.replacement(a.label) == self.replacement(b.label)
                            && self.operands_equal(&a.operands, &b.operands)
                    })
            }
            (
                InstructionKind::IfJump {
                    test: a,
                    operands: args_a,
                    true_label: yes_a,
                    false_label: no_a,
                    poll: poll_a,
                },
                InstructionKind::IfJump {
                    test: b,
                    operands: args_b,
                    true_label: yes_b,
                    false_label: no_b,
                    poll: poll_b,
                },
            ) => {
                a == b
                    && self.operands_equal(args_a, args_b)
                    && self.replacement(*yes_a) == self.replacement(*yes_b)
                    && self.replacement(*no_a) == self.replacement(*no_b)
                    && poll_a == poll_b
            }
            (
                InstructionKind::Jump {
                    operand: a,
                    arguments: args_a,
                    poll: poll_a,
                },
                InstructionKind::Jump {
                    operand: b,
                    arguments: args_b,
                    poll: poll_b,
                },
            ) => self.operand_equal(Some(*a), Some(*b)) && args_a == args_b && poll_a == poll_b,
            _ => false,
        }
    }
    fn block_equal(&self, first: usize, second: usize) -> bool {
        let first = &self.generator.blocks[first];
        let second = &self.generator.blocks[second];
        first.instructions.len() == second.instructions.len()
            && self.instruction_equal(first.label, second.label)
            && self.instruction_equal(first.branch.unwrap(), second.branch.unwrap())
            && first
                .instructions
                .iter()
                .zip(&second.instructions)
                .all(|(&a, &b)| self.instruction_equal(a, b))
    }
    fn fix_replacements(&self, old: usize, replacement: usize) {
        let mut cursor = &self.replacements;
        while let Some(link) = &cursor.0 {
            if link.pair.value.get() == old {
                link.pair.value.set(replacement);
            }
            cursor = &link.next;
        }
    }
    fn common_tail(&self, first: usize, second: usize) -> (Vec<usize>, Vec<usize>, Vec<usize>) {
        let mut first: Vec<_> = self.generator.blocks[first]
            .instructions
            .iter()
            .copied()
            .collect();
        let mut second: Vec<_> = self.generator.blocks[second]
            .instructions
            .iter()
            .copied()
            .collect();
        let mut tail = Vec::new();
        while let (Some(&a), Some(&b)) = (first.last(), second.last()) {
            if !self.instruction_equal(a, b) {
                break;
            }
            tail.push(first.pop().unwrap());
            second.pop();
        }
        tail.reverse();
        (first, second, tail)
    }
    fn extract_tail(
        &mut self,
        first: usize,
        second: usize,
        heads: (Vec<usize>, Vec<usize>, Vec<usize>),
    ) -> usize {
        let (head, other_head, tail) = heads;
        let number = self.generator.new_label();
        let branch = self.generator.blocks[first].branch.unwrap();
        let size = self.generator.tail_slots(&tail, branch);
        let previous = head
            .last()
            .copied()
            .unwrap_or(self.generator.blocks[first].label);
        let frame = self
            .generator
            .truncate_frame(&self.generator.instructions[previous].frame, size);
        let instr = self.generator.instruction(
            InstructionKind::Label {
                number,
                kind: LabelKind::Simple,
            },
            frame.clone(),
            None,
        );
        let block = self.generator.new_block(instr);
        self.generator.blocks[block].instructions = tail.into();
        self.generator.blocks[block].branch = Some(branch);
        self.generator.blocks[second].instructions = other_head.into();
        self.generator.blocks[first].instructions = head.into();
        for old in [second, first] {
            let jump = self.generator.instruction(
                InstructionKind::Jump {
                    operand: label(number),
                    arguments: None,
                    poll: false,
                },
                frame.clone(),
                None,
            );
            self.generator.blocks[old].branch = Some(jump);
        }
        self.changed = true;
        block
    }
    fn add(&mut self, block: usize, bucket: &Ids) -> Ids {
        let Some(cell) = &bucket.0 else {
            return Ids::cons(block, Ids::default());
        };
        let other = cell.id;
        let previous = self.replacements.clone();
        let number = self.generator.block_label(block);
        let replacement = self.generator.block_label(other);
        self.replacements.add(number, replacement);
        if self.block_equal(block, other) {
            self.fix_replacements(number, replacement);
            self.changed = true;
            return bucket.clone();
        }
        self.replacements = previous;
        let first_branch = self.generator.blocks[block].branch.unwrap();
        let second_branch = self.generator.blocks[other].branch.unwrap();
        if self.instruction_equal(first_branch, second_branch) {
            let heads = self.common_tail(block, other);
            if !heads.2.is_empty() {
                let new = self.extract_tail(block, other, heads);
                let rest = self.add(new, &cell.next);
                return Ids::cons(block, Ids::cons(other, rest));
            }
        }
        let rest = self.add(block, &cell.next);
        Ids::cons(other, rest)
    }
    fn run(&mut self) -> bool {
        let blocks: Vec<_> = self.generator.groups[self.generator.current_group]
            .blocks
            .iter()
            .copied()
            .collect();
        for block in blocks {
            let hash = self.block_hash(block);
            let bucket = self.table[hash].clone();
            self.table[hash] = self.add(block, &bucket);
        }
        let entry = self.generator.groups[self.generator.current_group].entry;
        self.generator.groups[self.generator.current_group].entry = self.replacement(entry);
        let mut result = Ids::default();
        for bucket in &self.table {
            for block in bucket.values() {
                self.generator.replace_labels(block, &self.replacements);
            }
            result = bucket.append(&result);
        }
        self.generator.groups[self.generator.current_group].blocks = result.values().into();
        self.changed
    }
}

// ---- Label-reference rewriting ----

impl Generator<'_, '_> {
    fn replacement_operand(&mut self, operand: usize, replacements: &Bindings) -> usize {
        if operand / 10_000 == 2 {
            let number = operand % 10_000;
            return label(
                replacements
                    .get(number)
                    .map(|pair| pair.value.get())
                    .unwrap_or(number),
            );
        }
        if let Some((base, index)) = self.operands.entry_if_closure(operand) {
            let base = self.replacement_operand(base, replacements);
            return self.operands.closure(base, index);
        }
        operand
    }
    fn replacement_operands(&mut self, operands: &Ids, replacements: &Bindings) -> Ids {
        let operands: Vec<_> = operands
            .values()
            .into_iter()
            .map(|operand| self.replacement_operand(operand, replacements))
            .collect();
        Ids::from_slice(&operands)
    }
    fn replacement_instruction(&mut self, instruction: usize, replacements: &Bindings) -> usize {
        let replace = |number| {
            replacements
                .get(number)
                .map(|pair| pair.value.get())
                .unwrap_or(number)
        };
        let kind = match self.instructions[instruction].kind.clone() {
            InstructionKind::Apply {
                primitive,
                operands,
                destination,
            } => InstructionKind::Apply {
                primitive,
                operands: self.replacement_operands(&operands, replacements),
                destination: destination
                    .map(|operand| self.replacement_operand(operand, replacements)),
            },
            InstructionKind::Copy {
                operand,
                destination,
            } => {
                let destination = self.replacement_operand(destination, replacements);
                let operand = self.replacement_operand(operand, replacements);
                InstructionKind::Copy {
                    operand,
                    destination,
                }
            }
            InstructionKind::Close(parameters) => {
                let mut new = Vec::new();
                for parameters in parameters {
                    let operands = self.replacement_operands(&parameters.operands, replacements);
                    let destination =
                        self.replacement_operand(parameters.destination, replacements);
                    new.push(Box::new(ClosureParameters {
                        destination,
                        label: replace(parameters.label),
                        operands,
                    }));
                }
                InstructionKind::Close(new)
            }
            InstructionKind::IfJump {
                test,
                operands,
                true_label,
                false_label,
                poll,
            } => InstructionKind::IfJump {
                test,
                operands: self.replacement_operands(&operands, replacements),
                true_label: replace(true_label),
                false_label: replace(false_label),
                poll,
            },
            InstructionKind::Jump {
                operand,
                arguments,
                poll,
            } => InstructionKind::Jump {
                operand: self.replacement_operand(operand, replacements),
                arguments,
                poll,
            },
            InstructionKind::Label { .. } => unreachable!(),
        };
        self.instruction(
            kind,
            self.instructions[instruction].frame.clone(),
            self.instructions[instruction].source,
        )
    }
    fn replace_labels(&mut self, block: usize, replacements: &Bindings) {
        let instructions: Vec<_> = self.blocks[block].instructions.iter().copied().collect();
        let instructions: VecDeque<_> = instructions
            .into_iter()
            .map(|instruction| self.replacement_instruction(instruction, replacements))
            .collect();
        self.blocks[block].instructions = instructions;
        let branch = self.replacement_instruction(self.blocks[block].branch.unwrap(), replacements);
        self.blocks[block].branch = Some(branch);
    }
}

// ---- Scheduling around direct predecessors and successors ----

struct BlockOrder<'g, 's, 'a> {
    generator: &'g mut Generator<'s, 'a>,
    left: Ids,
    ordered: VecDeque<usize>,
}
impl BlockOrder<'_, '_, '_> {
    fn take(&mut self, block: usize) -> usize {
        assert!(self.left.has(block));
        self.left = self.left.remove(block);
        block
    }
    fn predecessor(&self, block: usize) -> Option<usize> {
        let mut best = None;
        for candidate in self.generator.blocks[block].precedents.values() {
            if self.left.has(candidate)
                && best.is_none_or(|best| {
                    self.generator.exit_size(candidate) < self.generator.exit_size(best)
                })
            {
                best = Some(candidate);
            }
        }
        best
    }
    fn branches_to_label(&self, block: usize) -> bool {
        match self.generator.instructions[self.generator.blocks[block].branch.unwrap()].kind {
            InstructionKind::IfJump { .. } => true,
            InstructionKind::Jump { operand, .. } => operand / 10_000 == 2,
            _ => unreachable!(),
        }
    }
    fn successor(&self, block: usize) -> Option<usize> {
        match self.generator.instructions[self.generator.blocks[block].branch.unwrap()].kind {
            InstructionKind::IfJump {
                true_label,
                false_label,
                ..
            } => {
                let yes = self.generator.label_block(true_label);
                let no = self.generator.label_block(false_label);
                match (self.left.has(yes), self.left.has(no)) {
                    (true, true) => Some(if self.branches_to_label(yes) {
                        yes
                    } else if self.branches_to_label(no)
                        || self.generator.exit_size(yes) < self.generator.exit_size(no)
                    {
                        no
                    } else {
                        yes
                    }),
                    (true, false) => Some(yes),
                    (false, true) => Some(no),
                    (false, false) => None,
                }
            }
            InstructionKind::Jump { operand, .. } if operand / 10_000 == 2 => {
                let target = self.generator.label_block(operand % 10_000);
                self.left.has(target).then_some(target)
            }
            InstructionKind::Jump { .. } => None,
            _ => unreachable!(),
        }
    }
    fn references(&mut self, block: usize) {
        for reference in self.generator.blocks[block].references.values() {
            if self.left.has(reference) {
                self.take(reference);
                self.around(reference);
            }
        }
    }
    fn from(&mut self, block: usize) {
        self.ordered.push_back(block);
        if let Some(next) = self.successor(block) {
            self.take(next);
            self.around(next);
            if let Some(next) = self.successor(block) {
                self.take(next);
                self.around(next);
            }
        }
        self.references(block);
    }
    fn around(&mut self, block: usize) {
        if let Some(previous) = self.predecessor(block) {
            self.take(previous);
            let references = self.back(previous, Ids::default());
            self.ordered.push_back(previous);
            self.forward(block);
            for block in references.values() {
                self.references(block);
            }
        } else {
            self.from(block);
        }
    }
    fn back(&mut self, block: usize, references: Ids) -> Ids {
        let references = Ids::cons(block, references);
        if let Some(previous) = self.predecessor(block) {
            self.take(previous);
            let references = self.back(previous, references);
            self.ordered.push_back(previous);
            references
        } else {
            references
        }
    }
    fn forward(&mut self, block: usize) {
        self.ordered.push_back(block);
        if let Some(next) = self.successor(block) {
            self.take(next);
            self.forward(next);
            if let Some(next) = self.successor(block) {
                self.take(next);
                self.around(next);
            }
        }
        self.references(block);
    }
    fn run(&mut self) {
        let entry = self
            .generator
            .label_block(self.generator.groups[self.generator.current_group].entry);
        self.take(entry);
        self.from(entry);
        assert!(self.left.empty());
        let mut replacements = Bindings::default();
        for (i, &block) in self.ordered.iter().enumerate() {
            let instruction = self.generator.blocks[block].label;
            let InstructionKind::Label { number, .. } =
                &mut self.generator.instructions[instruction].kind
            else {
                unreachable!()
            };
            replacements.add(*number, i + 1);
            *number = i + 1;
        }
        for &block in &self.ordered {
            self.generator.replace_labels(block, &replacements);
        }
        let group = &mut self.generator.groups[self.generator.current_group];
        group.blocks = std::mem::take(&mut self.ordered);
        group.next_label = (group.next_label / 1000 + 1) * 1000;
    }
}

// ---- The original fixed-point purification pipeline ----

pub(super) struct Code {
    pub(super) block: usize,
    pub(super) instruction: usize,
    pub(super) slots_needed: usize,
}

impl Generator<'_, '_> {
    // Each source code/slot record has its own allocation and lifetime.
    #[allow(clippy::vec_box)]
    pub(super) fn code_list(&self, group: usize) -> Vec<Box<Code>> {
        let mut code = Vec::new();
        for &block in &self.groups[group].blocks {
            for instruction in std::iter::once(self.blocks[block].label)
                .chain(self.blocks[block].instructions.iter().copied())
                .chain(std::iter::once(self.blocks[block].branch.unwrap()))
            {
                code.push(Box::new(Code {
                    block,
                    instruction,
                    slots_needed: 0,
                }));
            }
        }
        // Each recorded branch seeds its block; labels end the backward walk.
        // This is the source's linear transfer, not successor-graph iteration.
        let mut needed = None;
        for code in code.iter_mut().rev() {
            match self.instructions[code.instruction].kind {
                InstructionKind::Label { .. } => {
                    code.slots_needed = needed.expect("label precedes a block body");
                    assert!(code.slots_needed <= self.instructions[code.instruction].frame.size);
                    needed = None;
                }
                InstructionKind::IfJump { .. } | InstructionKind::Jump { .. } => {
                    code.slots_needed = self.instructions[code.instruction].frame.size;
                    needed = Some(self.instruction_slots(code.instruction, code.slots_needed));
                }
                _ => {
                    code.slots_needed = needed.expect("instruction precedes its branch");
                    needed = Some(self.instruction_slots(code.instruction, code.slots_needed));
                }
            }
        }
        code
    }
    pub(super) fn purify(&mut self) {
        loop {
            self.remove_jump_cascades();
            self.remove_dead_blocks();
            let n = self.groups[self.current_group].blocks.len();
            let length = if n < 50 {
                43
            } else if n < 500 {
                403
            } else {
                4003
            };
            let mut common = CommonBlocks {
                generator: self,
                table: vec![Ids::default(); length],
                primitives: Ids::default(),
                replacements: Bindings::default(),
                changed: false,
            };
            let merged = common.run();
            let shortened = self.remove_useless_jumps();
            if merged || shortened {
                continue;
            }
            let left = Ids::from_slice(
                &self.groups[self.current_group]
                    .blocks
                    .iter()
                    .copied()
                    .collect::<Vec<_>>(),
            );
            BlockOrder {
                generator: self,
                left,
                ordered: VecDeque::new(),
            }
            .run();
            break;
        }
    }
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backward_slot_analysis_consumes_destinations_before_reading_operands() {
        let mut syntax = Compiler::new();
        let catalog = Catalog::new();
        let specials = Specials {
            return_var: syntax.variable(usize::MAX, "ret", Binding::Temporary),
            closure_var: syntax.variable(usize::MAX, "closure", Binding::Temporary),
            empty_var: syntax.variable(usize::MAX, "empty", Binding::Temporary),
        };
        let mut generator = Generator::new(&mut syntax, &catalog, OperandTable::new(), specials);
        let frame = generator.context.frame(Ids::default());
        let copy = generator.instruction(
            InstructionKind::Copy {
                operand: stack_slot(3),
                destination: stack_slot(4),
            },
            frame,
            None,
        );
        assert_eq!(generator.instruction_slots(copy, 4), 3);
        assert_eq!(generator.instruction_slots(copy, 5), 5);
        let nested = generator.operands.closure(stack_slot(6), 2);
        assert_eq!(generator.destination_slots(Some(nested), 1), 6);
        assert_eq!(generator.operand_slots(nested, 2), 6);
    }

    #[test]
    fn frame_truncation_shares_its_surviving_slot_suffix() {
        let mut syntax = Compiler::new();
        let catalog = Catalog::new();
        let specials = Specials {
            return_var: 0,
            closure_var: 1,
            empty_var: 2,
        };
        let generator = Generator::new(&mut syntax, &catalog, OperandTable::new(), specials);
        let slots = Ids::from_slice(&[7, 8, 9]);
        let frame = Frame {
            size: 3,
            slots: slots.clone(),
            registers: Ids::default(),
            closed: Ids::default(),
            live: Ids::default(),
        };
        let truncated = generator.truncate_frame(&frame, 2);
        assert_eq!(truncated.slots.values(), vec![8, 9]);
        assert!(Rc::ptr_eq(
            truncated.slots.0.as_ref().unwrap(),
            slots.0.as_ref().unwrap().next.0.as_ref().unwrap()
        ));
    }

    #[test]
    fn common_instruction_equality_deliberately_ignores_frame_alias_payloads() {
        let mut syntax = Compiler::new();
        let catalog = Catalog::new();
        let specials = Specials {
            return_var: 0,
            closure_var: 1,
            empty_var: 2,
        };
        let mut generator = Generator::new(&mut syntax, &catalog, OperandTable::new(), specials);
        let frame = |size, var| {
            Rc::new(Frame {
                size,
                slots: Ids::from_slice(&[var]),
                registers: Ids::from_slice(&[var]),
                closed: Ids::default(),
                live: Ids::from_slice(&[var]),
            })
        };
        let kind = InstructionKind::Copy {
            operand: 1,
            destination: 2,
        };
        let first = generator.instruction(kind.clone(), frame(1, 7), None);
        let second = generator.instruction(kind.clone(), frame(1, 8), None);
        let taller = generator.instruction(kind, frame(2, 7), None);
        let common = CommonBlocks {
            generator: &mut generator,
            table: vec![Ids::default(); 43],
            primitives: Ids::default(),
            replacements: Bindings::default(),
            changed: false,
        };
        assert!(common.instruction_equal(first, second));
        assert!(!common.instruction_equal(first, taller));
    }

    #[test]
    fn common_branch_equality_preserves_polling_and_call_argument_counts() {
        let mut syntax = Compiler::new();
        let catalog = Catalog::new();
        let specials = Specials {
            return_var: 0,
            closure_var: 1,
            empty_var: 2,
        };
        let mut generator = Generator::new(&mut syntax, &catalog, OperandTable::new(), specials);
        let frame = generator.context.frame(Ids::default());
        let first = generator.instruction(
            InstructionKind::Jump {
                operand: 0,
                arguments: None,
                poll: false,
            },
            frame.clone(),
            None,
        );
        let polled = generator.instruction(
            InstructionKind::Jump {
                operand: 0,
                arguments: None,
                poll: true,
            },
            frame.clone(),
            None,
        );
        let called = generator.instruction(
            InstructionKind::Jump {
                operand: 0,
                arguments: Some(0),
                poll: false,
            },
            frame,
            None,
        );
        let common = CommonBlocks {
            generator: &mut generator,
            table: vec![Ids::default(); 43],
            primitives: Ids::default(),
            replacements: Bindings::default(),
            changed: false,
        };
        assert!(!common.instruction_equal(first, polled));
        assert!(!common.instruction_equal(first, called));
    }
}
