//! Nonmoving storage for shared Snail values. The compiler publishes only
//! reference slots at calls and describes every reference-bearing field.
//! Numbers, packed arrays, padding and scoped scalar storage are never traced.
//! Allocation can collect. Entering a frame or registering a root cannot.

use std::{
    alloc::{Layout, alloc_zeroed, dealloc},
    cell::RefCell,
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
        Self::try_aligned(bytes, ALIGN)
    }

    fn try_aligned(bytes: usize, alignment: usize) -> Option<Self> {
        let layout = Layout::from_size_align(bytes, alignment).expect("GC allocation too large");
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
            memory: Memory::try_aligned(BLOCK, BLOCK)?,
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

// Each small-object block begins on a block boundary. Wasm32 needs at
// most 128K indices for its whole address space. Native test processes
// have sparse addresses, so only their occupied indices are stored.
#[derive(Default)]
struct BlockIndex {
    #[cfg(target_pointer_width = "32")]
    pages: Vec<u32>,
    #[cfg(not(target_pointer_width = "32"))]
    pages: std::collections::HashMap<usize, u32>,
}

impl BlockIndex {
    fn insert(&mut self, address: usize, index: usize) {
        let page = address / BLOCK;
        let entry = u32::try_from(index + 1).expect("too many heap blocks");
        #[cfg(target_pointer_width = "32")]
        {
            if self.pages.len() <= page {
                self.pages.resize(page + 1, 0);
            }
            self.pages[page] = entry;
        }
        #[cfg(not(target_pointer_width = "32"))]
        self.pages.insert(page, entry);
    }

    fn get(&self, address: usize) -> Option<usize> {
        let page = address / BLOCK;
        #[cfg(target_pointer_width = "32")]
        let entry = self.pages.get(page);
        #[cfg(not(target_pointer_width = "32"))]
        let entry = self.pages.get(&page);
        entry?.checked_sub(1).map(|index| index as usize)
    }

    fn rebuild(&mut self, blocks: &[Block]) {
        self.pages.clear();
        for (index, block) in blocks.iter().enumerate() {
            self.insert(block.memory.address(), index);
        }
    }
}

// ---- Explicit roots ----

struct Frame {
    chunk: usize,
    start: usize,
    length: usize,
    // The contiguous extent for frame-owned scalar records has no references.
    untraced: std::ops::Range<usize>,
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
    fn enter(&mut self, length: usize, untraced: std::ops::Range<usize>) -> usize {
        assert!(untraced.start <= untraced.end && untraced.end <= length);
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
        let slots = &mut self.chunks[chunk][start..start + length];
        if untraced.is_empty() {
            slots.fill(0);
        } else {
            slots[..untraced.start].fill(0);
            slots[untraced.end..].fill(0);
        }
        let address = self.chunks[chunk][start..].as_mut_ptr() as usize;
        self.frames.push(Frame {
            chunk,
            start,
            length,
            untraced,
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
            .flat_map(|frame| {
                let slots = &self.chunks[frame.chunk][frame.start..frame.start + frame.length];
                slots[..frame.untraced.start]
                    .iter()
                    .chain(&slots[frame.untraced.end..])
            })
            .chain(self.globals.values().flat_map(|slots| slots.iter()))
            .copied()
            .collect()
    }
}

// ---- Tracing and collection policy ----

// Tags are dense and local to this whole program. An ordinary record lists
// byte offsets of references. A reference array declares its repeated slot.
#[derive(Default, Clone)]
struct ObjectLayout {
    parent: u32,
    fields: Vec<usize>,
    reference_array: bool,
}

#[repr(C)]
#[derive(Default, Clone, Copy)]
struct Code {
    tag: u32,
    reserved: u32,
    index: u32,
}

#[derive(Default)]
struct Heap {
    layouts: Vec<ObjectLayout>,
    static_codes: Box<[Code]>,
    blocks: Vec<Block>,
    block_at: BlockIndex,
    large: BTreeMap<usize, Large>,
    roots: Roots,
    current: [usize; CLASSES],
    allocated: usize,
    live: usize,
    collections: usize,
    stress: bool,
    code: BTreeMap<usize, u32>,
    dead_code: Vec<u32>,
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

    // The compiler and host publish object starts. A scoped loan may point
    // to an active frame instead. Only managed allocations have a mark bit.
    fn mark(&mut self, address: usize) -> Option<usize> {
        if address == 0 || !address.is_multiple_of(ALIGN) {
            return None;
        }
        if let Some(index) = self.block_at.get(address) {
            let block = &mut self.blocks[index];
            let offset = address % BLOCK;
            if offset.is_multiple_of(block.stride) {
                let slot = offset / block.stride;
                if block.size[slot] != 0 && !std::mem::replace(&mut block.marked[slot], true) {
                    return Some(usize::from(block.size[slot]));
                }
            }
            return None;
        }
        let object = self.large.get_mut(&address)?;
        (!std::mem::replace(&mut object.marked, true)).then_some(object.memory.layout.size())
    }

    fn references(&self, address: usize, bytes: usize, pending: &mut Vec<usize>) {
        let tag = unsafe { (address as *const u32).read() } as usize;
        // Untyped foreign code descriptors contain only a table index.
        if tag == 0 {
            return;
        }
        let layout = &self.layouts[tag];
        if layout.reference_array {
            let count = unsafe { ((address + 4) as *const u32).read() } as usize;
            assert!(count <= (bytes - 8) / WORD);
            let slots = unsafe { std::slice::from_raw_parts((address + 8) as *const usize, count) };
            pending.extend(slots.iter().copied().filter(|&value| value != 0));
        } else {
            for &offset in &layout.fields {
                assert!(offset <= bytes - WORD);
                let value = unsafe { ((address + offset) as *const usize).read() };
                if value != 0 {
                    pending.push(value);
                }
            }
        }
    }

    fn collect(&mut self) {
        let started = self.profile.then(Instant::now);
        let mut pending = self.roots.values();
        while let Some(address) = pending.pop() {
            if let Some(bytes) = self.mark(address) {
                self.references(address, bytes, &mut pending);
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
        self.block_at.rebuild(&self.blocks);
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

    fn object_start(&self, address: usize) -> bool {
        if let Some(index) = self.block_at.get(address) {
            let block = &self.blocks[index];
            let offset = address % BLOCK;
            return offset.is_multiple_of(block.stride) && block.containing(offset).is_some();
        }
        self.large.contains_key(&address)
    }

    fn static_code(&self, address: usize) -> bool {
        let codes = self.static_codes.as_ptr_range();
        let start = codes.start as usize;
        (start..codes.end as usize).contains(&address)
            && (address - start).is_multiple_of(size_of::<Code>())
    }

    fn subtype(&self, mut tag: u32, expected: u32) -> bool {
        while tag != 0 && tag != expected {
            tag = self
                .layouts
                .get(tag as usize)
                .map_or(0, |layout| layout.parent);
        }
        tag != 0
    }

    fn sweep_code(&mut self) {
        for (address, index) in std::mem::take(&mut self.code) {
            if self.object_start(address) {
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
pub extern "C" fn enter(count: usize, start: usize, end: usize) -> usize {
    HEAP.with_borrow_mut(|heap| heap.roots.enter(count, start..end))
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
    HEAP.with(|cell| {
        // An abort inside the allocator leaves its Rust borrow active. Keep
        // the original terminal error when the host unwinds that invocation.
        if let Ok(mut heap) = cell.try_borrow_mut() {
            assert!(depth <= heap.roots.frames.len());
            heap.roots.frames.truncate(depth);
        }
    });
}

#[unsafe(export_name = "snail:gc/roots")]
pub extern "C" fn register(count: usize) -> usize {
    HEAP.with_borrow_mut(|heap| heap.roots.register(count))
}

// The compiler writes tag and table index for each address-taken function
// at startup. The instance owns these descriptors for its whole lifetime.
#[unsafe(export_name = "snail:gc/static-code")]
pub extern "C" fn static_code(count: usize) -> usize {
    HEAP.with_borrow_mut(|heap| {
        assert!(heap.static_codes.is_empty());
        heap.static_codes = vec![Code::default(); count].into_boxed_slice();
        heap.static_codes.as_ptr() as usize
    })
}

// A funcref supplied later by a host is the only code that needs reclaiming.
#[unsafe(export_name = "snail:gc/code-new")]
pub extern "C" fn new_code(index: u32) -> usize {
    assert!(index != 0);
    HEAP.with_borrow_mut(|heap| {
        let address = heap.allocate(size_of::<Code>());
        unsafe {
            (address as *mut Code).write(Code {
                index,
                ..Code::default()
            })
        };
        heap.code.insert(address, index);
        address
    })
}

// The host clears dead dynamic entries on return and before installing new
// code. Static entries are permanent. Normal allocation never touches the table.
#[unsafe(export_name = "snail:gc/dead-code")]
pub extern "C" fn dead_code() -> u32 {
    HEAP.with_borrow_mut(|heap| heap.dead_code.pop().unwrap_or(0))
}

#[unsafe(export_name = "snail:gc/release-roots")]
pub extern "C" fn release(address: usize) {
    HEAP.with_borrow_mut(|heap| {
        assert!(heap.roots.globals.remove(&address).is_some());
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

// ---- Program layouts ----

#[unsafe(export_name = "snail:gc/layouts")]
pub extern "C" fn layouts(count: usize) {
    HEAP.with_borrow_mut(|heap| {
        assert!(heap.layouts.is_empty());
        heap.layouts
            .resize(count.checked_add(1).unwrap(), ObjectLayout::default());
    })
}

#[unsafe(export_name = "snail:gc/reference-field")]
pub extern "C" fn reference_field(tag: usize, offset: usize) {
    assert!(offset >= 8 && offset.is_multiple_of(WORD));
    HEAP.with_borrow_mut(|heap| heap.layouts[tag].fields.push(offset));
}

#[unsafe(export_name = "snail:gc/reference-array")]
pub extern "C" fn reference_array(tag: usize) {
    HEAP.with_borrow_mut(|heap| heap.layouts[tag].reference_array = true);
}

#[unsafe(export_name = "snail:gc/type-parent")]
pub extern "C" fn type_parent(child: usize, parent: u32) {
    HEAP.with_borrow_mut(|heap| {
        assert!(parent != 0 && (parent as usize) < heap.layouts.len() && parent as usize != child);
        heap.layouts[child].parent = parent;
    });
}

/// The compiler supplies an actual object address in the heap or an active
/// root frame, or zero. Foreign values are checked separately before entry.
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
    HEAP.with_borrow(|heap| u32::from(heap.subtype(tag, expected)))
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
        HEAP.with_borrow(|heap| heap.static_code(address) || heap.code.contains_key(&address)),
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
        if heap.static_code(address) {
            return flags & 4 != 0;
        }
        heap.object_start(address) && heap.code.contains_key(&address) == (flags & 4 != 0)
    });
    if !valid {
        return 0;
    }
    let tag = unsafe { (address as *const u32).read() };
    u32::from(expected == 0 || HEAP.with_borrow(|heap| heap.subtype(tag, expected)))
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn layouts_trace_cycles_but_scalar_words_cannot_retain_an_object() {
        let mut heap = Heap::default();
        heap.layouts = vec![ObjectLayout::default(); 2];
        heap.layouts[1].fields.push(8);
        let root = heap.roots.enter(2, 1..2);
        let bytes = 8 + 2 * WORD;
        let a = heap.allocate(bytes);
        let b = heap.allocate(bytes);
        let dead = heap.allocate(bytes);
        unsafe {
            (a as *mut u32).write(1);
            (b as *mut u32).write(1);
            ((a + 8) as *mut usize).write(b);
            ((b + 8) as *mut usize).write(a);
            ((a + 8 + WORD) as *mut usize).write(dead);
            (root as *mut usize).write(a);
            ((root + WORD) as *mut usize).write(dead);
        }
        heap.collect();
        assert!(heap.object_start(a) && heap.object_start(b));
        assert!(!heap.object_start(dead));
        heap.roots.leave(root);
        heap.collect();
        assert_eq!(heap.live, 0);
        assert_eq!(heap.allocate(bytes), a);
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
        let first = roots.enter(1, 0..0);
        unsafe { (first as *mut usize).write(42) };
        let huge = roots.enter(50000, 0..0);
        assert_eq!(roots.values()[0], 42);
        roots.leave(huge);
        for _ in 0..10000 {
            let next = roots.enter(10, 0..0);
            roots.leave(next);
        }
        assert_eq!(roots.frames.len(), 1);
        roots.leave(first);
    }

    #[test]
    fn large_objects_are_traced_and_unregistered_globals_stop_retaining() {
        let mut heap = Heap::default();
        heap.layouts = vec![ObjectLayout::default(); 2];
        heap.layouts[1].reference_array = true;
        let root = heap.roots.register(1);
        let large = heap.allocate(BLOCK + 8);
        let small = heap.allocate(16);
        unsafe {
            (root as *mut usize).write(large);
            (large as *mut u32).write(1);
            ((large + 4) as *mut u32).write(1);
            ((large + 8) as *mut usize).write(small);
        }
        heap.collect();
        assert_eq!(heap.live, BLOCK + 8 + 16);
        heap.roots.globals.remove(&root);
        heap.collect();
        assert_eq!(heap.live, 0);
        assert!(heap.large.is_empty());
    }

    #[test]
    fn static_code_has_instance_lifetime_and_dynamic_entries_are_recycled() {
        HEAP.with_borrow_mut(|heap| *heap = Heap::default());
        let fixed = static_code(2);
        let dynamic = new_code(7);
        let root = enter(1, 0, 0);
        unsafe { (root as *mut usize).write(dynamic) };
        collect();
        assert_eq!(dead_code(), 0);
        assert_eq!(host_check(fixed, 0, 5), 1);
        assert_eq!(host_check(fixed + 1, 0, 5), 0);
        leave(root);
        collect();
        assert_eq!(live(), 0);
        assert_eq!(dead_code(), 7);
        assert_eq!(dead_code(), 0);
        assert_eq!(host_check(fixed, 0, 5), 1);
    }

    #[test]
    fn incoming_parameters_can_be_published_before_stress_collection() {
        HEAP.with_borrow_mut(|heap| *heap = Heap::default());
        let value = allocate(16, 0, 0);
        stress(1);
        let frame = enter(50000, 0, 0);
        assert_eq!(collections(), 0);
        unsafe { (frame as *mut usize).write(value) };
        allocate(16, 0, 0);
        HEAP.with_borrow(|heap| assert!(heap.object_start(value)));
        leave(frame);
        stress(0);
    }

    #[test]
    fn foreign_values_require_object_starts_and_the_logical_kind() {
        HEAP.with_borrow_mut(|heap| *heap = Heap::default());
        layouts(3);
        type_parent(2, 1);
        let object = allocate(17, 2, 0);
        assert_eq!(host_check(object, 1, 1), 1);
        assert_eq!(host_check(object, 3, 1), 0);
        assert_eq!(host_check(object + 1, 1, 1), 0);
        assert_eq!(host_check(object + 17, 1, 1), 0);
        assert_eq!(host_check(object, 1, 5), 0);
        assert_eq!(host_check(0, 1, 1), 0);
        assert_eq!(host_check(0, 1, 3), 1);
        let code = new_code(7);
        unsafe { (code as *mut u32).write(2) };
        assert_eq!(host_check(code, 1, 5), 1);
        assert_eq!(host_check(code, 3, 5), 0);
        assert_eq!(host_check(code, 1, 1), 0);
    }
}
