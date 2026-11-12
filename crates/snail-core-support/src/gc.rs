//! Nonmoving, conservative collection in the runtime's linear memory.
//!
//! Generated code publishes roots before calls. Neither Wasm's operand stack nor
//! Rust's stack is scanned. Managed allocation and explicit collection collect;
//! creating root frames, registering host roots and returning a result do not.
//! Fixed-size slots reuse dead objects without evacuation: ambiguous interior
//! addresses cannot be rewritten safely. Size classes avoid the severe line
//! fragmentation seen when self-hosting with conservative Immix roots.

use std::{
    alloc::{Layout, alloc_zeroed, dealloc},
    cell::{Cell, RefCell},
    collections::BTreeMap,
    mem::size_of,
    ptr::NonNull,
    time::Instant,
};

const BLOCK: usize = 32 * 1024;
const ALIGN: usize = 16;
const CLASSES: usize = 12; // 16 bytes through 32 KiB, inclusive.
const WORD: usize = size_of::<usize>();
const MIN_BUDGET: usize = 4 * 1024 * 1024;

// ---- Owned memory ----

struct Memory {
    pointer: NonNull<u8>,
    layout: Layout,
}

impl Memory {
    fn try_new(bytes: usize) -> Option<Self> {
        let layout = Layout::from_size_align(bytes, ALIGN).expect("GC allocation too large");
        let pointer = NonNull::new(unsafe { alloc_zeroed(layout) })?;
        Some(Self { pointer, layout })
    }

    fn address(&self) -> usize {
        self.pointer.as_ptr() as usize
    }

    fn zero(&self, offset: usize, bytes: usize) {
        assert!(offset <= self.layout.size() && bytes <= self.layout.size() - offset);
        unsafe { self.pointer.as_ptr().add(offset).write_bytes(0, bytes) };
    }
}

impl Drop for Memory {
    fn drop(&mut self) {
        unsafe { dealloc(self.pointer.as_ptr(), self.layout) };
    }
}

// ---- Blocks and allocation extents ----

struct Block {
    memory: Memory,
    stride: usize,
    size: Box<[u16]>,
    marked: Box<[bool]>,
    cursor: usize,
}

impl Block {
    fn try_new(stride: usize) -> Option<Self> {
        Some(Self {
            memory: Memory::try_new(BLOCK)?,
            stride,
            size: vec![0; BLOCK / stride].into_boxed_slice(),
            marked: vec![false; BLOCK / stride].into_boxed_slice(),
            cursor: 0,
        })
    }

    fn allocate(&mut self, bytes: usize) -> Option<usize> {
        assert!(bytes <= self.stride);
        while self.cursor < self.size.len() {
            let slot = self.cursor;
            self.cursor += 1;
            if self.size[slot] != 0 {
                continue;
            }
            self.size[slot] = bytes as u16;
            self.memory.zero(slot * self.stride, self.stride);
            return Some(self.memory.address() + slot * self.stride);
        }
        None
    }

    fn containing(&self, offset: usize) -> Option<usize> {
        let slot = offset / self.stride;
        let bytes = usize::from(*self.size.get(slot)?);
        (offset % self.stride < bytes).then_some(slot)
    }

    fn sweep(&mut self) -> usize {
        let mut live = 0;
        for (bytes, marked) in self.size.iter_mut().zip(self.marked.iter_mut()) {
            if *marked {
                live += usize::from(*bytes);
            } else {
                *bytes = 0;
            }
            *marked = false;
        }
        self.cursor = 0;
        live
    }
}

struct Large {
    memory: Memory,
    marked: bool,
}

// ---- Explicit roots ----

struct Frame {
    chunk: usize,
    start: usize,
    length: usize,
}

#[derive(Default)]
struct Roots {
    // Boxed chunks never move when the Vec grows. Frame pointers held in Wasm
    // locals therefore stay valid. Popped frames and unused tails are not roots.
    chunks: Vec<Box<[usize]>>,
    frames: Vec<Frame>,
    globals: BTreeMap<usize, Box<[usize]>>,
}

impl Roots {
    fn enter(&mut self, length: usize) -> usize {
        let (mut chunk, mut start) = self
            .frames
            .last()
            .map_or((0, 0), |f| (f.chunk, f.start + f.length));
        if self
            .chunks
            .get(chunk)
            .is_some_and(|c| c.len() - start < length)
        {
            chunk += 1;
            start = 0;
        }
        if chunk == self.chunks.len() {
            self.chunks
                .push(vec![0; length.max(16384)].into_boxed_slice());
        } else if self.chunks[chunk].len() < length {
            self.chunks[chunk] = vec![0; length].into_boxed_slice();
        }
        self.chunks[chunk][start..start + length].fill(0);
        let address = self.chunks[chunk][start..].as_mut_ptr() as usize;
        self.frames.push(Frame {
            chunk,
            start,
            length,
        });
        address
    }

    fn leave(&mut self, address: usize) {
        let frame = self.frames.pop().expect("GC root stack underflow");
        assert_eq!(
            self.chunks[frame.chunk][frame.start..].as_ptr() as usize,
            address
        );
    }

    fn register(&mut self, count: usize) -> usize {
        let mut slots = vec![0; count.max(1)].into_boxed_slice();
        let address = slots.as_mut_ptr() as usize;
        self.globals.insert(address, slots);
        address
    }

    fn values(&self) -> Vec<usize> {
        self.frames
            .iter()
            .flat_map(|f| self.chunks[f.chunk][f.start..f.start + f.length].iter())
            .chain(self.globals.values().flat_map(|slots| slots.iter()))
            .copied()
            .collect()
    }
}

// ---- Tracing and collection policy ----

#[derive(Default)]
struct Heap {
    blocks: Vec<Block>,
    block_at: BTreeMap<usize, usize>,
    large: BTreeMap<usize, Large>,
    roots: Roots,
    current: [usize; CLASSES],
    allocated: usize,
    live: usize,
    collections: usize,
    stress: bool,
    code: BTreeMap<usize, u32>,
    dead_code: Vec<u32>,
    free_code: Vec<u32>,
    modules: BTreeMap<u32, usize>,
    next_module: u32,
    profile: bool,
    profile_allocations: u64,
    profile_bytes: u64,
    pause_ns: u64,
    longest_pause_ns: u64,
}

impl Heap {
    fn allocate(&mut self, bytes: usize) -> usize {
        assert!(
            bytes > 0 && bytes <= isize::MAX as usize,
            "GC allocation too large"
        );
        if self.profile {
            self.profile_allocations += 1;
            self.profile_bytes += bytes as u64;
        }
        if self.stress || self.allocated.saturating_add(bytes) >= MIN_BUDGET.max(self.live / 2) {
            self.collect();
        }
        self.allocated = self.allocated.saturating_add(bytes);
        if bytes > BLOCK {
            // A large buffer needs contiguous allocator memory. Empty GC
            // blocks must be returned before failure: free slots alone cannot
            // satisfy this allocation, even when most of the heap is dead.
            let memory = Memory::try_new(bytes)
                .or_else(|| {
                    self.collect();
                    Memory::try_new(bytes)
                })
                .unwrap_or_else(|| {
                    panic!(
                        "linear GC exhausted: requested {bytes} bytes, {} live bytes",
                        self.live
                    )
                });
            let address = memory.address();
            self.large.insert(
                address,
                Large {
                    memory,
                    marked: false,
                },
            );
            return address;
        }
        self.allocate_small(bytes)
    }

    fn allocate_hole(&mut self, bytes: usize, class: usize) -> Option<usize> {
        while self.current[class] < self.blocks.len() {
            let block = &mut self.blocks[self.current[class]];
            if block.stride == ALIGN << class
                && let Some(address) = block.allocate(bytes)
            {
                return Some(address);
            }
            self.current[class] += 1;
        }
        None
    }

    fn allocate_small(&mut self, bytes: usize) -> usize {
        let stride = bytes.max(ALIGN).next_power_of_two();
        let class = stride.trailing_zeros() as usize - ALIGN.trailing_zeros() as usize;
        if let Some(address) = self.allocate_hole(bytes, class) {
            return address;
        }
        let block = match Block::try_new(stride) {
            Some(block) => block,
            None => {
                self.collect();
                if let Some(address) = self.allocate_hole(bytes, class) {
                    return address;
                }
                Block::try_new(stride).unwrap_or_else(|| {
                    panic!(
                        "linear GC exhausted: requested {bytes} bytes, {} live bytes",
                        self.live
                    )
                })
            }
        };
        self.block_at
            .insert(block.memory.address(), self.blocks.len());
        self.blocks.push(block);
        self.blocks[self.current[class]].allocate(bytes).unwrap()
    }

    fn mark(&mut self, candidate: usize, work: &mut Vec<(usize, usize)>) {
        if let Some((&base, &index)) = self.block_at.range(..=candidate).next_back() {
            let block = &mut self.blocks[index];
            if let Some(start) = block.containing(candidate - base) {
                if !block.marked[start] {
                    block.marked[start] = true;
                    work.push((base + start * block.stride, usize::from(block.size[start])));
                }
                return;
            }
        }
        if let Some((&base, object)) = self.large.range_mut(..=candidate).next_back()
            && candidate - base < object.memory.layout.size()
            && !object.marked
        {
            object.marked = true;
            work.push((base, object.memory.layout.size()));
        }
    }

    fn collect(&mut self) {
        let started = self.profile.then(Instant::now);
        let mut work = Vec::new();
        for candidate in self.roots.values() {
            self.mark(candidate, &mut work);
        }
        while let Some((address, bytes)) = work.pop() {
            for offset in (0..bytes.saturating_sub(WORD - 1)).step_by(WORD) {
                let candidate = unsafe { ((address + offset) as *const usize).read() };
                self.mark(candidate, &mut work);
            }
        }
        self.live = 0;
        let mut spare = false;
        self.blocks.retain_mut(|block| {
            let live = block.sweep();
            self.live += live;
            let keep = live != 0 || !spare;
            spare |= live == 0;
            keep
        });
        self.block_at = self
            .blocks
            .iter()
            .enumerate()
            .map(|(index, block)| (block.memory.address(), index))
            .collect();
        self.large.retain(|_, object| {
            let marked = object.marked;
            if marked {
                self.live += object.memory.layout.size();
            }
            object.marked = false;
            marked
        });
        self.current = [0; CLASSES];
        self.allocated = 0;
        self.collections += 1;
        self.sweep_code();
        if let Some(started) = started {
            let elapsed = started.elapsed().as_nanos() as u64;
            self.pause_ns += elapsed;
            self.longest_pause_ns = self.longest_pause_ns.max(elapsed);
        }
    }

    fn contains(&self, address: usize) -> bool {
        if let Some((&base, &index)) = self.block_at.range(..=address).next_back()
            && self.blocks[index].containing(address - base).is_some()
        {
            return true;
        }
        self.large
            .range(..=address)
            .next_back()
            .is_some_and(|(&base, object)| address - base < object.memory.layout.size())
    }

    fn object_start(&self, address: usize) -> bool {
        if let Some((&base, &index)) = self.block_at.range(..=address).next_back() {
            let block = &self.blocks[index];
            let offset = address - base;
            if offset % block.stride == 0 && block.containing(offset).is_some() {
                return true;
            }
        }
        self.large.contains_key(&address)
    }

    fn sweep_code(&mut self) {
        for (address, index) in std::mem::take(&mut self.code) {
            if self.contains(address) {
                self.code.insert(address, index);
            } else {
                self.dead_code.push(index);
            }
        }
    }
}

// ---- Runtime ABI ----

thread_local! {
    static HEAP: RefCell<Heap> = RefCell::new(Heap::default());
}

#[unsafe(export_name = "snail:gc/alloc")]
pub extern "C" fn allocate(bytes: usize, tag: u32, length: u32) -> usize {
    assert!(bytes >= 8);
    HEAP.with_borrow_mut(|heap| {
        let address = heap.allocate(bytes);
        unsafe {
            (address as *mut u32).write(tag);
            ((address + 4) as *mut u32).write(length);
        }
        address
    })
}

#[unsafe(export_name = "snail:gc/array")]
pub extern "C" fn allocate_array(tag: u32, length: u32, stride: u32) -> usize {
    let bytes = (length as usize)
        .checked_mul(stride as usize)
        .and_then(|bytes| bytes.checked_add(8))
        .expect("GC array size overflow");
    allocate(bytes, tag, length)
}

#[unsafe(export_name = "snail:gc/enter")]
pub extern "C" fn enter(count: usize) -> usize {
    HEAP.with_borrow_mut(|heap| heap.roots.enter(count))
}

#[unsafe(export_name = "snail:gc/leave")]
pub extern "C" fn leave(address: usize) {
    HEAP.with_borrow_mut(|heap| heap.roots.leave(address));
}

#[unsafe(export_name = "snail:gc/checkpoint")]
pub extern "C" fn checkpoint() -> usize {
    HEAP.with_borrow(|heap| heap.roots.frames.len())
}

// Hosts restore a checkpoint after a trapped invocation. An ordinary return or
// tail call pops its own frame; a Wasm trap bypasses those instructions.
#[unsafe(export_name = "snail:gc/restore")]
pub extern "C" fn restore(depth: usize) {
    HEAP.with_borrow_mut(|heap| {
        assert!(depth <= heap.roots.frames.len());
        heap.roots.frames.truncate(depth);
    });
}

#[unsafe(export_name = "snail:gc/roots")]
pub extern "C" fn register(count: usize) -> usize {
    HEAP.with_borrow_mut(|heap| heap.roots.register(count))
}

// A module's globals and code handles occupy one managed object. An active
// module has a registered root; an old closure keeps its module alive through
// its code handle after the loader releases that root. This preserves old
// code's globals across live reload without retaining every retired module.
#[unsafe(export_name = "snail:gc/module")]
pub extern "C" fn register_module(count: usize) -> usize {
    let bytes = count
        .checked_mul(WORD)
        .and_then(|n| n.checked_add(8))
        .expect("module root size overflow");
    HEAP.with_borrow_mut(|heap| {
        let address = heap.allocate(bytes);
        heap.roots
            .globals
            .insert(address, vec![address].into_boxed_slice());
        heap.modules.insert(heap.next_module, address);
        heap.next_module = heap
            .next_module
            .checked_add(1)
            .expect("too many module instances");
        address
    })
}

#[unsafe(export_name = "snail:gc/code-new")]
pub extern "C" fn new_code(index: u32, tag: u32, owner: usize) -> usize {
    assert!(index != 0);
    HEAP.with_borrow_mut(|heap| {
        let address = heap.allocate(8 + 2 * WORD);
        unsafe {
            (address as *mut u32).write(tag);
            ((address + 8) as *mut usize).write(index as usize);
            ((address + 8 + WORD) as *mut usize).write(owner);
        }
        heap.code.insert(address, index);
        address
    })
}

// The generated allocation wrapper clears these table entries before making
// their indices reusable. Rust never traces or mutates Wasm function refs.
#[unsafe(export_name = "snail:gc/dead-code")]
pub extern "C" fn dead_code() -> u32 {
    HEAP.with_borrow_mut(|heap| heap.dead_code.pop().unwrap_or(0))
}

#[unsafe(export_name = "snail:gc/recycle-code")]
pub extern "C" fn recycle_code(index: u32) {
    assert!(index != 0);
    HEAP.with_borrow_mut(|heap| heap.free_code.push(index));
}

#[unsafe(export_name = "snail:gc/free-code")]
pub extern "C" fn free_code() -> u32 {
    HEAP.with_borrow_mut(|heap| heap.free_code.pop().unwrap_or(0))
}

#[unsafe(export_name = "snail:gc/release-roots")]
pub extern "C" fn release(address: usize) {
    HEAP.with_borrow_mut(|heap| {
        assert!(heap.roots.globals.remove(&address).is_some());
        heap.modules.retain(|_, root| *root != address);
    });
}

#[unsafe(export_name = "snail:gc/module-checkpoint")]
pub extern "C" fn module_checkpoint() -> u32 {
    HEAP.with_borrow(|heap| heap.next_module)
}

// Instantiation is synchronous. A failed start function cannot publish its
// module; the host releases only registrations made during that attempt.
#[unsafe(export_name = "snail:gc/rollback-modules")]
pub extern "C" fn rollback_modules(checkpoint: u32) {
    HEAP.with_borrow_mut(|heap| {
        for (_, address) in heap.modules.split_off(&checkpoint) {
            heap.roots.globals.remove(&address);
        }
    });
}

#[unsafe(export_name = "snail:gc/collect")]
pub extern "C" fn collect() {
    HEAP.with_borrow_mut(Heap::collect);
}

#[unsafe(export_name = "snail:gc/stress")]
pub extern "C" fn stress(enabled: u32) {
    HEAP.with_borrow_mut(|heap| heap.stress = enabled != 0);
}

#[unsafe(export_name = "snail:gc/live")]
pub extern "C" fn live() -> usize {
    HEAP.with_borrow(|heap| heap.live)
}

#[unsafe(export_name = "snail:gc/collections")]
pub extern "C" fn collections() -> usize {
    HEAP.with_borrow(|heap| heap.collections)
}

// Timing runs leave profiling off. A separate diagnostic run measures work and
// pauses, so counter updates and clock imports are not part of reported timing.
#[unsafe(export_name = "snail:gc/profile")]
pub extern "C" fn profile(enabled: u32) {
    HEAP.with_borrow_mut(|heap| {
        heap.profile = enabled != 0;
        heap.profile_allocations = 0;
        heap.profile_bytes = 0;
        heap.pause_ns = 0;
        heap.longest_pause_ns = 0;
    });
}

#[unsafe(export_name = "snail:gc/profile-allocations")]
pub extern "C" fn profile_allocations() -> u64 {
    HEAP.with_borrow(|heap| heap.profile_allocations)
}

#[unsafe(export_name = "snail:gc/profile-bytes")]
pub extern "C" fn profile_bytes() -> u64 {
    HEAP.with_borrow(|heap| heap.profile_bytes)
}

#[unsafe(export_name = "snail:gc/pause-ns")]
pub extern "C" fn pause_ns() -> u64 {
    HEAP.with_borrow(|heap| heap.pause_ns)
}

#[unsafe(export_name = "snail:gc/longest-pause-ns")]
pub extern "C" fn longest_pause_ns() -> u64 {
    HEAP.with_borrow(|heap| heap.longest_pause_ns)
}

#[unsafe(export_name = "snail:gc/heap-bytes")]
pub extern "C" fn heap_bytes() -> usize {
    HEAP.with_borrow(|heap| {
        heap.blocks.len() * BLOCK
            + heap
                .large
                .values()
                .map(|object| object.memory.layout.size())
                .sum::<usize>()
    })
}

#[unsafe(export_name = "snail:gc/allocated")]
pub extern "C" fn allocated() -> usize {
    HEAP.with_borrow(|heap| heap.allocated)
}

#[unsafe(export_name = "snail:gc/root-words")]
pub extern "C" fn root_words() -> usize {
    HEAP.with_borrow(|heap| {
        heap.roots
            .frames
            .iter()
            .map(|frame| frame.length)
            .sum::<usize>()
            + heap
                .roots
                .globals
                .values()
                .map(|slots| slots.len())
                .sum::<usize>()
    })
}

// ---- Shared type identities ----

// A recursion group's text uses local positions for its members, and its
// dependencies name previously interned groups. Equality checks the full key;
// a hash collision can never change the meaning of a cast after a reload.
#[derive(Default)]
struct Types {
    scratch: Vec<u8>,
    dependencies: Vec<u32>,
    groups: BTreeMap<(Vec<u8>, Vec<u32>), (u32, u32)>,
    parents: Vec<u32>,
}

thread_local! {
    static TYPES: RefCell<Types> = RefCell::new(Types::default());
    static ABI_FAILED: Cell<bool> = const { Cell::new(false) };
}

// Reference types become i32 at the engine boundary. A generated start function
// compares logical signatures before publishing its module. The host translates
// this specific failure back to a link error, preserving ordinary start traps.
#[unsafe(export_name = "snail:gc/abi-failed")]
pub extern "C" fn abi_failed() {
    ABI_FAILED.set(true);
}

#[unsafe(export_name = "snail:gc/abi-error")]
pub extern "C" fn abi_error() -> u32 {
    u32::from(ABI_FAILED.replace(false))
}

#[unsafe(export_name = "snail:gc/type-key")]
pub extern "C" fn type_key(length: usize) -> usize {
    TYPES.with_borrow_mut(|types| {
        types.scratch.resize(length, 0);
        types.dependencies.clear();
        types.scratch.as_mut_ptr() as usize
    })
}

#[unsafe(export_name = "snail:gc/type-dependency")]
pub extern "C" fn type_dependency(tag: u32) {
    TYPES.with_borrow_mut(|types| types.dependencies.push(tag));
}

#[unsafe(export_name = "snail:gc/type-group")]
pub extern "C" fn type_group(count: u32) -> u32 {
    TYPES.with_borrow_mut(|types| {
        let key = (
            types.scratch.clone(),
            std::mem::take(&mut types.dependencies),
        );
        if let Some(&(base, previous_count)) = types.groups.get(&key) {
            assert_eq!(previous_count, count);
            return base;
        }
        let base = u32::try_from(types.parents.len() + 1).expect("too many runtime types");
        types
            .parents
            .resize(types.parents.len() + count as usize, 0);
        types.groups.insert(key, (base, count));
        base
    })
}

#[unsafe(export_name = "snail:gc/type-parent")]
pub extern "C" fn type_parent(child: u32, parent: u32) {
    TYPES.with_borrow_mut(|types| {
        assert!(parent > 0 && parent as usize <= types.parents.len() && parent != child);
        let old = &mut types.parents[child as usize - 1];
        assert!(*old == 0 || *old == parent);
        *old = parent;
    });
}

fn subtype(types: &Types, mut tag: u32, expected: u32) -> bool {
    while tag != 0 && tag != expected {
        tag = types.parents.get(tag as usize - 1).copied().unwrap_or(0);
    }
    tag != 0
}

/// The compiler supplies an actual object address in the heap or an active
/// root frame, or zero. Conservative
/// candidate recognition is confined to tracing; it never grants access here.
#[unsafe(export_name = "snail:gc/test")]
pub extern "C" fn test_type(address: usize, expected: u32, nullable: u32) -> u32 {
    if address == 0 {
        return u32::from(nullable != 0);
    }
    let tag = unsafe { (address as *const u32).read() };
    // Most casts recover an exact closure or data layout. Its canonical tag
    // proves that case without borrowing the registry or walking its parents.
    if tag != 0 && tag == expected {
        return 1;
    }
    TYPES.with_borrow(|types| u32::from(subtype(types, tag, expected)))
}

#[unsafe(export_name = "snail:gc/cast")]
pub extern "C" fn cast(address: usize, expected: u32, nullable: u32) -> usize {
    assert!(
        test_type(address, expected, nullable) != 0,
        "invalid managed cast"
    );
    address
}

#[unsafe(export_name = "snail:gc/code-cast")]
pub extern "C" fn cast_code(address: usize, expected: u32, nullable: u32) -> usize {
    if address == 0 {
        assert!(nullable != 0, "null function reference");
        return 0;
    }
    assert!(
        HEAP.with_borrow(|heap| heap.code.contains_key(&address)),
        "invalid code handle"
    );
    // A raw foreign function has no Snail layout descriptor. `unsafe-cast`
    // accepts its caller's ABI promise; call_indirect still checks its numeric
    // Wasm signature. Compiled Snail functions always carry a nonzero identity.
    if unsafe { (address as *const u32).read() } == 0 {
        return address;
    }
    cast(address, expected, nullable)
}

// Host handles are checked at the foreign boundary. Generated field operations
// already carry the compiler's layout proof and do not repeat this lookup.
#[unsafe(export_name = "snail:gc/host-check")]
pub extern "C" fn host_check(address: usize, expected: u32, flags: u32) -> u32 {
    if address == 0 {
        return u32::from(flags & 2 != 0);
    }
    let valid = HEAP.with_borrow(|heap| {
        heap.object_start(address) && heap.code.contains_key(&address) == (flags & 4 != 0)
    });
    if !valid {
        return 0;
    }
    let tag = unsafe { (address as *const u32).read() };
    u32::from(expected == 0 || TYPES.with_borrow(|types| subtype(types, tag, expected)))
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn interior_roots_trace_cycles_and_dead_objects_are_reused() {
        let mut heap = Heap::default();
        let root = heap.roots.enter(1);
        let a = heap.allocate(2 * WORD);
        let b = heap.allocate(2 * WORD);
        unsafe {
            (a as *mut usize).write(b + 1);
            (b as *mut usize).write(a + WORD);
            (root as *mut usize).write(a + 1);
        }
        heap.collect();
        assert_eq!(heap.live, 4 * WORD);
        heap.roots.leave(root);
        heap.collect();
        assert_eq!(heap.live, 0);
        assert_eq!(heap.allocate(2 * WORD), a);
        assert_eq!(unsafe { (a as *const usize).read() }, 0);
    }

    #[test]
    fn exact_extents_exclude_padding_and_one_past() {
        let mut block = Block::try_new(32).unwrap();
        block.allocate(17).unwrap();
        assert_eq!(block.containing(16), Some(0));
        assert_eq!(block.containing(17), None);
        assert_eq!(block.containing(31), None);
        assert_eq!(block.containing(usize::MAX), None);
    }

    #[test]
    fn dead_slots_among_survivors_are_reused_without_touching_survivors() {
        let mut block = Block::try_new(32).unwrap();
        for index in 0..BLOCK / 32 {
            let address = block.allocate(24).unwrap();
            unsafe { (address as *mut usize).write(index) };
            block.marked[index] = index % 4 == 0;
        }
        assert_eq!(block.sweep(), BLOCK / 128 * 24);
        for _ in 0..BLOCK / 32 * 3 / 4 {
            let address = block.allocate(24).expect("dead slots are reusable");
            assert_ne!((address - block.memory.address()) % 128, 0);
        }
        assert!(block.allocate(24).is_none());
        for offset in (0..BLOCK).step_by(128) {
            assert_eq!(
                unsafe { ((block.memory.address() + offset) as *const usize).read() },
                offset / 32
            );
        }
    }

    #[test]
    fn frame_growth_preserves_addresses_and_tail_handoffs_bound_depth() {
        let mut roots = Roots::default();
        let first = roots.enter(1);
        unsafe { (first as *mut usize).write(42) };
        let huge = roots.enter(50000);
        assert_eq!(roots.values()[0], 42);
        roots.leave(huge);
        for _ in 0..10000 {
            let next = roots.enter(10);
            roots.leave(next);
        }
        assert_eq!(roots.frames.len(), 1);
        roots.leave(first);
    }

    #[test]
    fn large_objects_are_traced_and_unregistered_globals_stop_retaining() {
        let mut heap = Heap::default();
        let root = heap.roots.register(1);
        let large = heap.allocate(BLOCK + 1);
        let small = heap.allocate(WORD);
        unsafe {
            (root as *mut usize).write(large + BLOCK);
            (large as *mut usize).write(small);
        }
        heap.collect();
        assert_eq!(heap.live, BLOCK + 1 + WORD);
        heap.roots.globals.remove(&root);
        heap.collect();
        assert_eq!(heap.live, 0);
        assert!(heap.large.is_empty());
    }

    #[test]
    fn old_code_keeps_its_module_and_imported_globals_alive() {
        HEAP.with_borrow_mut(|heap| *heap = Heap::default());
        let imported = register_module(1);
        let old = register_module(1);
        let value = allocate(16, 0, 0);
        unsafe {
            ((imported + 8) as *mut usize).write(value);
            ((old + 8) as *mut usize).write(imported);
        }
        let code = new_code(7, 0, old);
        let root = enter(1);
        unsafe { (root as *mut usize).write(code) };
        release(old);
        release(imported);
        collect();
        HEAP.with_borrow(|heap| {
            assert!(heap.contains(value));
            assert!(heap.contains(old));
        });
        assert_eq!(dead_code(), 0);
        leave(root);
        collect();
        assert_eq!(live(), 0);
        assert_eq!(free_code(), 0);
        assert_eq!(dead_code(), 7);
        recycle_code(7);
        assert_eq!(free_code(), 7);
    }

    #[test]
    fn incoming_parameters_can_be_published_before_stress_collection() {
        HEAP.with_borrow_mut(|heap| *heap = Heap::default());
        let value = allocate(16, 0, 0);
        stress(1);
        let frame = enter(50000);
        assert_eq!(collections(), 0);
        unsafe { (frame as *mut usize).write(value) };
        allocate(16, 0, 0);
        HEAP.with_borrow(|heap| assert!(heap.contains(value)));
        leave(frame);
        stress(0);
    }

    #[test]
    fn foreign_values_require_object_starts_and_the_logical_kind() {
        HEAP.with_borrow_mut(|heap| *heap = Heap::default());
        TYPES.with_borrow_mut(|types| {
            *types = Types::default();
            types.parents = vec![0, 1, 0];
        });
        let object = allocate(17, 2, 0);
        assert_eq!(host_check(object, 1, 1), 1);
        assert_eq!(host_check(object, 3, 1), 0);
        assert_eq!(host_check(object + 1, 1, 1), 0);
        assert_eq!(host_check(object + 17, 1, 1), 0);
        assert_eq!(host_check(object, 1, 5), 0);
        assert_eq!(host_check(0, 1, 1), 0);
        assert_eq!(host_check(0, 1, 3), 1);
        let code = new_code(7, 2, 0);
        assert_eq!(host_check(code, 1, 5), 1);
        assert_eq!(host_check(code, 3, 5), 0);
        assert_eq!(host_check(code, 1, 1), 0);
    }
}
