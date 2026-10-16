//! Nonmoving Immix collection for the native target.
//!
//! Exact frames and declared heap edges are the only roots. Each region owns
//! its mapping and maps; objects never cross regions or change their address.

use crate::native::{NativeRoots, NativeTable, native_trap};
use std::{ffi::c_void, ptr, time::Instant};

// ---- Heap representation ----

pub(crate) const BLOCK_SIZE: usize = 32768;
const LINE_SIZE: usize = 128;
const LINES: usize = BLOCK_SIZE / LINE_SIZE;
const ALIGNMENT: usize = 16;
const START_WORDS: usize = BLOCK_SIZE / ALIGNMENT / 64;
const ALLOCATED: u64 = 1;
const MARKED: u64 = 2;
const CONTINUATION: usize = usize::MAX;

#[derive(Clone)]
struct Block {
    starts: [u64; START_WORDS],
    lines: [u8; LINES],
    span: usize,
    live_lines: usize,
    available_lines: usize,
    next_line: usize,
}

impl Default for Block {
    fn default() -> Self {
        Self {
            starts: [0; START_WORDS],
            lines: [0; LINES],
            span: 0,
            live_lines: 0,
            available_lines: 0,
            next_line: 0,
        }
    }
}

struct Region {
    arena: *mut u8,
    blocks: Vec<Block>,
    used_blocks: usize,
    search_block: usize,
    search_large: usize,
}

impl Drop for Region {
    fn drop(&mut self) {
        unsafe { libc::munmap(self.arena.cast(), self.blocks.len() * BLOCK_SIZE) };
    }
}

pub(crate) enum Layout {
    Fields(Vec<u32>),
    ReferenceArray,
}

#[derive(Default)]
pub(crate) struct Metadata {
    pub layouts: Vec<Layout>,
    pub globals: Vec<*const u64>,
    pub tables: Vec<*const NativeTable>,
}

pub type Finalizer = unsafe extern "C" fn(*mut c_void, *mut c_void);

struct Watch {
    object: *mut c_void,
    data: *mut c_void,
    callback: Finalizer,
}

#[derive(Clone, Copy)]
pub(crate) struct Config {
    pub initial: usize,
    pub maximum: usize,
    pub limit: usize,
    pub minimum_budget: usize,
    pub statistics: bool,
}

#[derive(Default)]
struct Statistics {
    collections: usize,
    live_bytes: usize,
    live_objects: usize,
    occupied_bytes: usize,
    allocated_bytes: usize,
    allocated_objects: usize,
    peak_live: usize,
    root_visits: usize,
    field_visits: usize,
    reused_holes: usize,
    large_objects: usize,
    mark_seconds: f64,
    sweep_seconds: f64,
}

pub(crate) struct Collector {
    regions: Vec<Region>,
    search_region: usize,
    // A small bump range retains its owner when a large allocation uses another
    // region. Reserving its entire line hole prevents overlapping allocations.
    bump_region: usize,
    cursor: *mut u8,
    limit: *mut u8,
    heap_bytes: usize,
    config: Config,
    since_collection: usize,
    budget: usize,
    work: Vec<*mut u64>,
    watches: Vec<Watch>,
    metadata: Metadata,
    stats: Statistics,
    #[cfg(test)]
    allocation_failures: AllocationFailures,
}

fn aligned_size(bytes: usize) -> usize {
    (bytes + 8 + ALIGNMENT - 1) & !(ALIGNMENT - 1)
}

impl Collector {
    pub fn new(config: Config, metadata: Metadata) -> Option<Self> {
        let mut heap = Self {
            regions: Vec::new(),
            search_region: 0,
            bump_region: 0,
            cursor: ptr::null_mut(),
            limit: ptr::null_mut(),
            heap_bytes: 0,
            config,
            since_collection: 0,
            budget: config.minimum_budget,
            work: Vec::new(),
            watches: Vec::new(),
            metadata,
            stats: Statistics::default(),
            #[cfg(test)]
            allocation_failures: AllocationFailures::default(),
        };
        heap.add_region(config.initial).then_some(heap)
    }

    fn record_start(&mut self, region: usize, header: *mut u64) {
        let region = &mut self.regions[region];
        let offset = header as usize - region.arena as usize;
        let index = offset % BLOCK_SIZE / ALIGNMENT;
        region.blocks[offset / BLOCK_SIZE].starts[index / 64] |= 1 << (index % 64);
    }

    // ---- Region growth ----

    // Prepare metadata and mapping before publication. Failure preserves all
    // existing objects and cursors. Metadata is outside the managed-byte cap.
    fn add_region(&mut self, bytes: usize) -> bool {
        if self.regions.try_reserve(1).is_err() {
            return false;
        }
        let Some(region) = self.reserve_region(bytes) else {
            return false;
        };
        self.regions.push(region);
        self.search_region = self.regions.len() - 1;
        self.heap_bytes += bytes;
        true
    }

    fn reserve_region(&mut self, bytes: usize) -> Option<Region> {
        let mut blocks = Vec::new();
        #[cfg(test)]
        if self.allocation_failures.metadata {
            return None;
        }
        blocks.try_reserve_exact(bytes / BLOCK_SIZE).ok()?;
        blocks.resize_with(bytes / BLOCK_SIZE, Block::default);
        let arena = self.map_region(bytes)?;
        Some(Region {
            arena,
            blocks,
            used_blocks: 0,
            search_block: 0,
            search_large: 0,
        })
    }

    fn map_region(&mut self, bytes: usize) -> Option<*mut u8> {
        #[cfg(test)]
        {
            self.allocation_failures.attempts += 1;
            if self.allocation_failures.mapping || bytes > self.allocation_failures.mapping_limit {
                return None;
            }
        }
        let arena = unsafe {
            libc::mmap(
                ptr::null_mut(),
                bytes,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_PRIVATE | libc::MAP_ANONYMOUS,
                -1,
                0,
            )
        };
        (arena != libc::MAP_FAILED).then_some(arena.cast())
    }

    fn grow_heap(&mut self, bytes: usize) -> bool {
        let needed = bytes.div_ceil(BLOCK_SIZE) * BLOCK_SIZE;
        let remaining = self.config.maximum - self.heap_bytes;
        if needed > remaining {
            return false;
        }
        let preferred = self.heap_bytes.max(needed).min(remaining);
        self.add_region(preferred) || (preferred != needed && self.add_region(needed))
    }

    // ---- Block and line allocation ----

    fn claim_hole(&mut self, region: usize, index: usize, first: usize, end: usize) {
        let owner = &mut self.regions[region];
        let block = &mut owner.blocks[index];
        self.stats.reused_holes += usize::from(block.live_lines != 0);
        block.lines[first..end].fill(1);
        block.span = 1;
        block.available_lines -= end - first;
        block.next_line = end;
        self.bump_region = region;
        self.cursor = unsafe { owner.arena.add(index * BLOCK_SIZE + first * LINE_SIZE) };
        self.limit = unsafe { owner.arena.add(index * BLOCK_SIZE + end * LINE_SIZE) };
        owner.search_block = index;
        owner.used_blocks = owner.used_blocks.max(index + 1);
    }

    fn find_hole(
        &mut self,
        region: usize,
        index: usize,
        mut first: usize,
        stop: usize,
        bytes: usize,
    ) -> bool {
        while first < stop {
            let block = &self.regions[region].blocks[index];
            while first < stop && block.lines[first] != 0 {
                first += 1;
            }
            let mut end = first;
            while end < stop && block.lines[end] == 0 {
                end += 1;
            }
            if (end - first) * LINE_SIZE >= bytes {
                self.claim_hole(region, index, first, end);
                return true;
            }
            first = end;
        }
        false
    }

    fn acquire_hole(&mut self, region: usize, bytes: usize) -> bool {
        let count = self.regions[region].blocks.len();
        let start = self.regions[region].search_block;
        for checked in 0..count {
            let index = (start + checked) % count;
            let block = &mut self.regions[region].blocks[index];
            if block.span == 0 {
                block.available_lines = LINES;
                self.claim_hole(region, index, 0, LINES);
                return true;
            }
            if block.span != 1 || block.available_lines * LINE_SIZE < bytes {
                continue;
            }
            let next = block.next_line; // A consumed hole separates these ranges.
            if self.find_hole(region, index, next, LINES, bytes)
                || self.find_hole(region, index, 0, next, bytes)
            {
                return true;
            }
        }
        false
    }

    fn find_large(
        &mut self,
        region: usize,
        mut first: usize,
        stop: usize,
        span: usize,
    ) -> Option<*mut u64> {
        while first + span <= stop {
            let blocks = &self.regions[region].blocks;
            let mut end = first;
            while end < first + span && blocks[end].span == 0 {
                end += 1;
            }
            if end == first + span {
                return Some(self.claim_large(region, first, end));
            }
            let occupied = blocks[end].span;
            first = end
                + if occupied == CONTINUATION {
                    1
                } else {
                    occupied
                };
        }
        None
    }

    fn claim_large(&mut self, region: usize, first: usize, end: usize) -> *mut u64 {
        let owner = &mut self.regions[region];
        owner.blocks[first].span = end - first;
        for block in &mut owner.blocks[first + 1..end] {
            block.span = CONTINUATION;
        }
        owner.used_blocks = owner.used_blocks.max(end);
        owner.search_large = end;
        self.stats.large_objects += 1;
        let header = unsafe { owner.arena.add(first * BLOCK_SIZE).cast() };
        self.record_start(region, header);
        header
    }

    fn allocate_large(&mut self, region: usize, bytes: usize) -> Option<*mut u64> {
        let owner = &self.regions[region];
        let (next, count) = (owner.search_large, owner.blocks.len());
        let span = bytes.div_ceil(BLOCK_SIZE);
        self.find_large(region, next, count, span)
            .or_else(|| self.find_large(region, 0, next, span))
    }

    fn allocate_bump(&mut self, bytes: usize) -> *mut u64 {
        let header = self.cursor.cast();
        self.cursor = unsafe { self.cursor.add(bytes) };
        self.record_start(self.bump_region, header);
        header
    }

    #[inline(never)]
    fn allocate_slow(&mut self, bytes: usize) -> Option<*mut u64> {
        let first = self.search_region;
        loop {
            if bytes > BLOCK_SIZE {
                if let Some(header) = self.allocate_large(self.search_region, bytes) {
                    return Some(header);
                }
            } else if self.acquire_hole(self.search_region, bytes) {
                return Some(self.allocate_bump(bytes));
            }
            self.search_region = (self.search_region + self.regions.len() - 1) % self.regions.len();
            if self.search_region == first {
                return None;
            }
        }
    }

    fn allocate_header(&mut self, bytes: usize) -> Option<*mut u64> {
        if self.cursor.is_null() || self.limit as usize - (self.cursor as usize) < bytes {
            self.allocate_slow(bytes)
        } else {
            Some(self.allocate_bump(bytes))
        }
    }

    #[inline(never)]
    unsafe fn retry_allocation(
        &mut self,
        bytes: usize,
        collected: bool,
        roots: *mut NativeRoots,
    ) -> Option<*mut u64> {
        if !collected {
            unsafe { self.collect(roots) };
        }
        // Headroom uses occupied space, including unusable large-object tails.
        // Optional growth failure must still permit reuse of reclaimed holes.
        let crowded = self.stats.occupied_bytes > self.heap_bytes - self.heap_bytes / 4;
        if crowded {
            self.grow_heap(bytes);
        }
        let header = self.allocate_header(bytes);
        if header.is_none() && !crowded && self.grow_heap(bytes) {
            self.allocate_header(bytes)
        } else {
            header
        }
    }

    pub unsafe fn allocate(&mut self, bytes: usize, roots: *mut NativeRoots) -> *mut u64 {
        // Two low header bits hold flags. This bound also makes alignment,
        // block rounding and collection-budget arithmetic safe before mutation.
        if bytes > usize::MAX / 4 || aligned_size(bytes) > self.config.maximum {
            return ptr::null_mut();
        }
        let collected = self.since_collection >= self.budget;
        if collected {
            unsafe { self.collect(roots) };
        }
        let extent = aligned_size(bytes);
        let header = self
            .allocate_header(extent)
            .or_else(|| unsafe { self.retry_allocation(extent, collected, roots) });
        let Some(header) = header else {
            return ptr::null_mut();
        };
        unsafe {
            header.write((bytes as u64) << 2 | ALLOCATED);
            ptr::write_bytes(header.add(1).cast::<u8>(), 0, bytes);
        }
        self.since_collection += extent;
        self.stats.allocated_bytes += bytes;
        self.stats.allocated_objects += 1;
        unsafe { header.add(1) }
    }

    // ---- Explicit roots and tracing ----

    fn containing_region(&self, value: u64) -> Option<usize> {
        // Only exact payload starts qualify: eight bytes after an aligned header.
        if value as usize % ALIGNMENT != 8 {
            return None;
        }
        self.regions.iter().rposition(|region| {
            (value as usize).wrapping_sub(region.arena as usize) < region.used_blocks * BLOCK_SIZE
        })
    }

    unsafe fn candidate(&self, region: usize, value: u64) -> Option<*mut u64> {
        let owner = &self.regions[region];
        let offset = value as usize - owner.arena as usize;
        let index = (offset - 8) % BLOCK_SIZE / ALIGNMENT;
        if owner.blocks[offset / BLOCK_SIZE].starts[index / 64] & (1 << (index % 64)) == 0 {
            return None;
        }
        let header = unsafe { (value as *mut u64).sub(1) };
        (unsafe { *header } & ALLOCATED != 0).then_some(header)
    }

    unsafe fn mark_lines(&mut self, region: usize, header: *mut u64) {
        let owner = &mut self.regions[region];
        let offset = header as usize - owner.arena as usize;
        let end = (offset + aligned_size((unsafe { *header } >> 2) as usize)).div_ceil(LINE_SIZE);
        for line in offset / LINE_SIZE..end {
            owner.blocks[line / LINES].lines[line % LINES] = 1;
        }
    }

    unsafe fn mark(&mut self, value: u64) {
        let Some(region) = self.containing_region(value) else {
            return;
        };
        let Some(header) = (unsafe { self.candidate(region, value) }) else {
            return;
        };
        if unsafe { *header } & MARKED != 0 {
            return;
        }
        unsafe {
            *header |= MARKED;
            self.mark_lines(region, header);
        }
        if self.work.try_reserve(1).is_err() {
            native_trap();
        }
        self.work.push(unsafe { header.add(1) });
    }

    unsafe fn mark_roots(&mut self, mut frame: *mut NativeRoots) {
        while !frame.is_null() {
            let roots = unsafe { &*frame };
            assert!(roots.count <= roots.capacity);
            self.stats.root_visits += roots.count as usize;
            for index in 0..roots.count as usize {
                unsafe { self.mark(*roots.values.as_ptr().add(index)) };
            }
            frame = roots.previous;
        }
        self.stats.root_visits += self.metadata.globals.len();
        for index in 0..self.metadata.globals.len() {
            unsafe { self.mark(*self.metadata.globals[index]) };
        }
        for index in 0..self.metadata.tables.len() {
            let table = unsafe { &*self.metadata.tables[index] };
            self.stats.root_visits += table.length as usize;
            for cell in 0..table.length as usize {
                unsafe { self.mark(*table.values.add(cell)) };
            }
        }
    }

    unsafe fn trace_object(&mut self, words: *mut u64) {
        let count = (unsafe { *words.sub(1) } >> 5) as usize;
        // Exact-base membership authorizes the header, not an arbitrary payload
        // read. Even an invalid guest layout must fail before leaving its extent.
        if count == 0 {
            native_trap();
        }
        let type_id = (unsafe { *words } >> 2) as usize;
        if type_id == 0 || type_id > self.metadata.layouts.len() {
            native_trap();
        }
        match &self.metadata.layouts[type_id - 1] {
            Layout::ReferenceArray => {
                assert!(count >= 2);
                let length = unsafe { *words.add(1) } as usize;
                assert!(length <= count - 2);
                self.stats.field_visits += length;
                for index in 0..length {
                    unsafe { self.mark(*words.add(index + 2)) };
                }
            }
            Layout::Fields(fields) => {
                let length = fields.len();
                // Collection is single-threaded, with no marking callbacks.
                // mark neither mutates nor mutably borrows layouts or offsets,
                // so this owned storage stays valid while the worklist grows.
                let offsets = fields.as_ptr();
                self.stats.field_visits += length;
                for index in 0..length {
                    let offset = unsafe { *offsets.add(index) } as usize;
                    assert!(offset < count);
                    unsafe { self.mark(*words.add(offset)) };
                }
            }
        }
    }

    // ---- Weak cleanup and line reclamation ----

    pub fn watch(
        &mut self,
        object: *mut c_void,
        callback: Option<Finalizer>,
        data: *mut c_void,
    ) -> (Option<Finalizer>, *mut c_void) {
        let old = self
            .watches
            .iter()
            .position(|watch| watch.object == object)
            .map(|index| self.watches.remove(index));
        if let Some(callback) = callback {
            if self.watches.try_reserve(1).is_err() {
                native_trap();
            }
            self.watches.push(Watch {
                object,
                data,
                callback,
            });
        }
        old.map_or((None, ptr::null_mut()), |watch| {
            (Some(watch.callback), watch.data)
        })
    }

    unsafe fn queue_finalizers(&mut self) {
        let mut index = self.watches.len();
        while index > 0 {
            index -= 1;
            let object = self.watches[index].object as u64;
            let header = self
                .containing_region(object)
                .and_then(|region| unsafe { self.candidate(region, object) });
            if header.is_some_and(|header| unsafe { *header } & MARKED == 0) {
                let watch = self.watches.remove(index);
                // Finalizers only queue scalar IDs. They cannot allocate or
                // reenter this collector, and never own their managed wrapper.
                unsafe { (watch.callback)(watch.object, watch.data) };
            }
        }
    }

    unsafe fn sweep_starts(&mut self, region: usize, index: usize) {
        let owner = &mut self.regions[region];
        let block = &mut owner.blocks[index];
        for word in 0..START_WORDS {
            let mut starts = block.starts[word];
            while starts != 0 {
                let bit = starts.trailing_zeros() as usize;
                let header = unsafe {
                    owner
                        .arena
                        .add(index * BLOCK_SIZE + (word * 64 + bit) * ALIGNMENT)
                        .cast::<u64>()
                };
                if unsafe { *header } & MARKED != 0 {
                    unsafe {
                        *header &= !MARKED;
                    }
                    self.stats.live_bytes += (unsafe { *header } >> 2) as usize;
                    self.stats.live_objects += 1;
                } else {
                    block.starts[word] &= !(1 << bit);
                    unsafe {
                        *header = 0;
                    }
                }
                starts &= starts - 1;
            }
        }
    }

    unsafe fn sweep_region(&mut self, region: usize) {
        for index in 0..self.regions[region].used_blocks {
            let live_lines = self.regions[region].blocks[index]
                .lines
                .iter()
                .filter(|&&line| line != 0)
                .count();
            if live_lines == 0 {
                // Tracing marks every line of a live allocation, including
                // large continuations. Finalizers ran before this sweep;
                // clearing exact membership makes stale headers unreachable.
                self.regions[region].blocks[index].starts.fill(0);
            } else {
                unsafe { self.sweep_starts(region, index) };
            }
            let block = &mut self.regions[region].blocks[index];
            block.live_lines = live_lines;
            if live_lines == 0 {
                block.span = 0;
            }
            // Live large continuation and tail blocks stay entirely reserved.
            self.stats.occupied_bytes += if block.span > 1 {
                BLOCK_SIZE
            } else {
                block.live_lines * LINE_SIZE
            };
            block.available_lines = LINES - block.live_lines;
            block.next_line = 0;
        }
        self.regions[region].search_block = 0;
        self.regions[region].search_large = 0;
    }

    unsafe fn sweep(&mut self) {
        self.stats.live_bytes = 0;
        self.stats.live_objects = 0;
        self.stats.occupied_bytes = 0;
        for region in (0..self.regions.len()).rev() {
            unsafe { self.sweep_region(region) };
        }
        self.cursor = ptr::null_mut();
        self.limit = ptr::null_mut();
        self.search_region = self.regions.len() - 1;
    }

    pub unsafe fn collect(&mut self, roots: *mut NativeRoots) {
        let start = self.config.statistics.then(Instant::now);
        for region in &mut self.regions {
            for block in &mut region.blocks[..region.used_blocks] {
                block.lines.fill(0);
            }
        }
        unsafe { self.mark_roots(roots) };
        while let Some(words) = self.work.pop() {
            unsafe { self.trace_object(words) };
        }
        let marked = self.config.statistics.then(Instant::now);
        unsafe {
            self.queue_finalizers();
            self.sweep();
        }
        if let (Some(start), Some(marked)) = (start, marked) {
            self.stats.mark_seconds += marked.duration_since(start).as_secs_f64();
            self.stats.sweep_seconds += marked.elapsed().as_secs_f64();
        }
        self.stats.collections += 1;
        self.stats.peak_live = self.stats.peak_live.max(self.stats.live_bytes);
        self.budget = self
            .stats
            .live_bytes
            .saturating_mul(2)
            .max(self.config.minimum_budget);
        self.since_collection = 0;
    }

    pub fn collections(&self) -> usize {
        self.stats.collections
    }

    // ---- Opt-in measurements ----

    pub fn report_statistics(&self) {
        if !self.config.statistics {
            return;
        }
        let arena_used: usize = self
            .regions
            .iter()
            .map(|region| region.used_blocks * BLOCK_SIZE)
            .sum();
        let s = &self.stats;
        eprintln!(
            concat!(
                "immix-gc allocation_search=tuned evacuation=0 heap_bytes={} initial_heap_bytes={} ",
                "heap_limit={} regions={} growths={} collections={} allocations={} bytes={} ",
                "arena_used={} last_live={} last_occupied={} peak_live={} live_objects={} roots={} fields={} ",
                "holes_reused={} large_allocations={} mark_s={:.6} sweep_s={:.6}"
            ),
            self.heap_bytes,
            self.config.initial,
            self.config.limit,
            self.regions.len(),
            self.regions.len() - 1,
            s.collections,
            s.allocated_objects,
            s.allocated_bytes,
            arena_used,
            s.live_bytes,
            s.occupied_bytes,
            s.peak_live,
            s.live_objects,
            s.root_visits,
            s.field_visits,
            s.reused_holes,
            s.large_objects,
            s.mark_seconds,
            s.sweep_seconds
        );
    }
}

// ---- Configuration ----

fn configured_bytes(name: &str, fallback: usize) -> usize {
    std::env::var_os(name).map_or(fallback, |text| {
        text.to_str()
            .and_then(parse_bytes)
            .unwrap_or_else(|| native_trap())
    })
}

fn parse_bytes(text: &str) -> Option<usize> {
    let text = text.trim_start_matches([' ', '\t', '\r', '\n', '\x0b', '\x0c']);
    if text.starts_with('-') {
        return None;
    }
    text.parse::<usize>().ok().filter(|&bytes| bytes != 0)
}

fn configured_heap_bytes(name: &str, fallback: usize) -> usize {
    let bytes = configured_bytes(name, fallback);
    if !(BLOCK_SIZE..=usize::MAX / 4).contains(&bytes) {
        native_trap();
    }
    bytes / BLOCK_SIZE * BLOCK_SIZE
}

impl Config {
    pub fn from_environment() -> Self {
        let limit = if std::env::var_os("SNAIL_GC_HEAP_BYTES").is_some() {
            configured_heap_bytes("SNAIL_GC_HEAP_BYTES", 0)
        } else {
            0
        };
        let maximum = if limit != 0 {
            limit
        } else {
            usize::MAX / 4 / BLOCK_SIZE * BLOCK_SIZE
        };
        let initial = configured_heap_bytes(
            "SNAIL_GC_INITIAL_BYTES",
            if limit != 0 { limit } else { 256 * 1024 * 1024 },
        );
        if initial > maximum {
            native_trap();
        }
        Self {
            initial,
            maximum,
            limit,
            minimum_budget: configured_bytes("SNAIL_GC_MIN_BYTES", 8 * 1024 * 1024),
            statistics: std::env::var_os("SNAIL_GC_STATS").is_some(),
        }
    }
}

// ---- Tests ----

#[cfg(test)]
struct AllocationFailures {
    metadata: bool,
    mapping: bool,
    mapping_limit: usize,
    attempts: usize,
}

#[cfg(test)]
impl Default for AllocationFailures {
    fn default() -> Self {
        Self {
            metadata: false,
            mapping: false,
            mapping_limit: usize::MAX,
            attempts: 0,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[repr(C)]
    struct Frame {
        header: NativeRoots,
        values: [u64; 256],
    }

    struct Heap {
        collector: Collector,
        frame: Box<Frame>,
        finalized: Box<[usize; 16]>,
    }

    impl Heap {
        fn new(initial: usize, maximum: usize) -> Self {
            let config = Config {
                initial: initial * BLOCK_SIZE,
                maximum: maximum * BLOCK_SIZE,
                limit: maximum * BLOCK_SIZE,
                minimum_budget: 8 * 1024 * 1024,
                statistics: false,
            };
            let metadata = Metadata {
                layouts: vec![
                    Layout::Fields(vec![1]),
                    Layout::Fields(vec![]),
                    Layout::ReferenceArray,
                ],
                ..Metadata::default()
            };
            Self {
                collector: Collector::new(config, metadata).unwrap(),
                frame: Box::new(Frame {
                    header: NativeRoots {
                        previous: ptr::null_mut(),
                        capacity: 256,
                        count: 256,
                        values: [],
                    },
                    values: [0; 256],
                }),
                finalized: Box::new([0; 16]),
            }
        }

        fn allocate(&mut self, bytes: usize) -> *mut u64 {
            unsafe { self.collector.allocate(bytes, &mut self.frame.header) }
        }

        fn object(&mut self, bytes: usize, kind: u64, value: u64) -> *mut u64 {
            let words = self.allocate(bytes);
            assert!(!words.is_null());
            unsafe {
                assert!(
                    std::slice::from_raw_parts(words.cast::<u8>(), bytes)
                        .iter()
                        .all(|&byte| byte == 0)
                );
                words.write(kind);
                if bytes >= 16 {
                    words.add(1).write(value);
                }
            }
            words
        }

        fn collect(&mut self) {
            unsafe { self.collector.collect(&mut self.frame.header) };
        }

        fn watch(&mut self, words: *mut u64, index: usize) {
            self.collector.watch(
                words.cast(),
                Some(finalize),
                (&mut self.finalized[index] as *mut usize).cast(),
            );
        }
    }

    unsafe extern "C" fn finalize(_object: *mut c_void, data: *mut c_void) {
        unsafe {
            *data.cast::<usize>() += 1;
        }
    }

    #[test]
    fn exact_roots_trace_declared_edges_globals_tables_and_reference_arrays() {
        let mut heap = Heap::new(8, 8);
        let mut permanent = 0_u64;
        let mut cells = [0_u64];
        let mut table = NativeTable {
            values: cells.as_mut_ptr(),
            length: 1,
            maximum: 1,
        };
        heap.collector.metadata.globals.push(&mut permanent);
        heap.collector.metadata.tables.push(&mut table);
        let parent = heap.object(16, 6, 0);
        heap.frame.values[0] = parent as u64;
        let child = heap.object(16, 10, parent as u64);
        unsafe {
            *parent.add(1) = child as u64;
        }
        heap.watch(parent, 0);
        heap.watch(child, 1);
        heap.collect();
        assert_eq!(&heap.finalized[..2], &[0, 0]);
        heap.frame.values[0] = child as u64;
        heap.collect();
        assert_eq!(&heap.finalized[..2], &[1, 0]); // Numeric pointer shapes are not edges.
        heap.frame.values[0] = 0;
        heap.collect();
        assert_eq!(&heap.finalized[..2], &[1, 1]);
        let cycle = heap.object(16, 6, 0);
        unsafe {
            *cycle.add(1) = cycle as u64;
        }
        cells[0] = cycle as u64;
        heap.watch(cycle, 2);
        heap.collect();
        assert_eq!(heap.finalized[2], 0);
        permanent = cells[0];
        cells[0] = 0;
        assert_ne!(permanent, 0);
        assert_eq!(cells[0], 0);
        heap.collect();
        assert_eq!(heap.finalized[2], 0);
        permanent = 0;
        heap.collect();
        assert_eq!(heap.finalized[2], 1);
        let array = heap.object(16 + 20000 * 8, 15, 20000);
        heap.frame.values[0] = array as u64;
        let child = heap.object(16, 10, 0);
        unsafe {
            *array.add(20001) = child as u64;
        }
        heap.watch(child, 3);
        heap.collect();
        assert_eq!(heap.finalized[3], 0);
        heap.frame.values[1] = array as u64;
        heap.frame.header.count = 0;
        heap.collect();
        assert_eq!(heap.finalized[3], 1);
        let reused = heap.object(16 + 20000 * 8, 15, 20000);
        assert_eq!(reused, array);
        heap.frame.header.count = 1;
        heap.frame.values[0] = reused as u64;
        let mut immortal = [10_u64, 0];
        heap.watch(immortal.as_mut_ptr(), 4);
        heap.collect();
        assert_eq!(heap.finalized[4], 0);
        let (old, data) = heap
            .collector
            .watch(immortal.as_mut_ptr().cast(), None, ptr::null_mut());
        assert!(old.is_some());
        assert_eq!(data, (&mut heap.finalized[4] as *mut usize).cast());
        assert_eq!(permanent, 0);
    }

    #[test]
    fn cached_fields_survive_worklist_growth_and_ignore_undeclared_words() {
        let mut heap = Heap::new(8, 8);
        let offsets = vec![15, 1, 13, 3, 11, 5, 9, 7];
        heap.collector.metadata.layouts[0] = Layout::Fields(offsets.clone());
        let parent = heap.object(17 * 8, 6, 0);
        heap.frame.values[0] = parent as u64;
        for (index, offset) in offsets.iter().enumerate() {
            let child = heap.object(8, 10, 0); // Tag-only object, empty descriptor.
            unsafe { parent.add(*offset as usize).write(child as u64) };
            heap.watch(child, index);
        }
        let decoy = heap.object(8, 10, 0);
        unsafe { parent.add(2).write(decoy as u64) };
        heap.watch(decoy, 8);
        heap.collector.work = Vec::with_capacity(1);
        let starting_capacity = heap.collector.work.capacity();
        assert!(starting_capacity < offsets.len());
        heap.collect();
        assert!(heap.collector.work.capacity() > starting_capacity);
        assert_eq!(heap.collector.stats.field_visits, offsets.len());
        assert_eq!(heap.collector.stats.live_objects, offsets.len() + 1);
        assert_eq!(&heap.finalized[..9], &[0, 0, 0, 0, 0, 0, 0, 0, 1]);
        heap.frame.values[0] = 0;
        heap.collect();
        assert_eq!(heap.collector.stats.live_objects, 0);
        assert_eq!(&heap.finalized[..9], &[1; 9]);
    }

    #[test]
    #[should_panic(expected = "assertion failed: offset < count")]
    fn field_offset_at_extent_panics_before_payload_read() {
        let mut heap = Heap::new(1, 1);
        heap.collector.metadata.layouts[0] = Layout::Fields(vec![2]);
        heap.frame.values[0] = heap.object(16, 6, 0) as u64;
        heap.collect();
    }

    #[test]
    #[should_panic(expected = "assertion failed: offset < count")]
    fn extreme_field_offset_panics_before_payload_read() {
        let mut heap = Heap::new(1, 1);
        heap.collector.metadata.layouts[0] = Layout::Fields(vec![u32::MAX]);
        heap.frame.values[0] = heap.object(16, 6, 0) as u64;
        heap.collect();
    }

    #[test]
    fn retained_lines_reclaim_holes_without_moving_live_objects() {
        let mut heap = Heap::new(1, 1);
        let first = heap.object(16, 10, 123);
        heap.frame.values[0] = first as u64;
        let mut last = ptr::null_mut();
        for index in 0..999 {
            last = heap.object(16, 10, index);
        }
        heap.frame.values[1] = last as u64;
        heap.collect();
        let middle = heap.object(16, 10, 456);
        assert!((middle as usize) > first as usize && (middle as usize) < last as usize);
        assert!(middle as usize - first as usize >= LINE_SIZE);
        heap.frame.values[1] = middle as u64;
        for index in 0..4000 {
            heap.object(16, 10, index);
        }
        heap.collect();
        unsafe {
            assert_eq!((*first.add(1), *middle.add(1)), (123, 456));
        }
    }

    #[test]
    fn smaller_hole_search_wraps_without_triggering_collection() {
        let mut heap = Heap::new(1, 1);
        let mut base = 0;
        for line in 0..256 {
            let value = heap.object(120, 10, line as u64);
            if line == 0 {
                base = value as usize;
            }
            if line != 1 && !(3..=10).contains(&line) {
                heap.frame.values[line] = value as u64;
            }
        }
        heap.collect();
        let collections = heap.collector.collections();
        let large = heap.object(1016, 10, 900);
        assert_eq!(large as usize, base + 3 * LINE_SIZE);
        heap.frame.values[3] = large as u64;
        let small = heap.object(16, 10, 901);
        assert_eq!(small as usize, base + LINE_SIZE);
        assert_eq!(heap.collector.collections(), collections);
        heap.frame.values[1] = small as u64;
        heap.collect();
        unsafe {
            assert_eq!((*large.add(1), *small.add(1)), (900, 901));
        }
    }

    #[test]
    fn large_search_wraps_to_earlier_free_blocks() {
        let mut heap = Heap::new(8, 8);
        let first = heap.object(2 * BLOCK_SIZE - 8, 10, 1);
        let separator = heap.object(BLOCK_SIZE - 8, 10, 2);
        heap.frame.values[0] = separator as u64;
        let later = heap.object(3 * BLOCK_SIZE - 8, 10, 3);
        let last = heap.object(2 * BLOCK_SIZE - 8, 10, 4);
        heap.frame.values[1] = last as u64;
        heap.collect();
        let collections = heap.collector.collections();
        let three = heap.object(3 * BLOCK_SIZE - 8, 10, 5);
        heap.frame.values[2] = three as u64;
        let two = heap.object(2 * BLOCK_SIZE - 8, 10, 6);
        heap.frame.values[3] = two as u64;
        assert_eq!((three, two), (later, first));
        assert_eq!(heap.collector.collections(), collections);
        heap.collect();
        unsafe {
            assert_eq!(
                (*separator.add(1), *last.add(1), *three.add(1), *two.add(1)),
                (2, 4, 5, 6)
            );
        }
    }

    #[test]
    fn allocation_boundaries_include_headers_and_preserve_bump_tail() {
        let mut heap = Heap::new(8, 8);
        let sizes = [
            16,
            BLOCK_SIZE,
            16,
            BLOCK_SIZE - 72,
            BLOCK_SIZE - 8,
            BLOCK_SIZE - 24,
            8,
            BLOCK_SIZE - 7,
        ];
        let mut values = Vec::new();
        for (index, bytes) in sizes.into_iter().enumerate() {
            let value = heap.object(bytes, 10, index as u64);
            heap.frame.values[index] = value as u64;
            values.push(value as usize);
        }
        assert_eq!(values[2], values[0] + 32);
        assert_eq!(values[3], values[2] + 32);
        assert_eq!(values[4], values[0] + 3 * BLOCK_SIZE);
        assert_eq!(values[6], values[5] + BLOCK_SIZE - 16);
        assert_eq!(values[7], values[0] + 5 * BLOCK_SIZE);
        let collections = heap.collector.collections();
        assert!(heap.allocate(BLOCK_SIZE).is_null());
        assert_eq!(heap.collector.collections(), collections + 1);
        assert_eq!(heap.object(16, 10, 8) as usize, values[0] + 7 * BLOCK_SIZE);
        for (index, value) in values.into_iter().enumerate() {
            if index != 6 {
                unsafe {
                    assert_eq!(*(value as *mut u64).add(1), index as u64);
                }
            }
        }
    }

    #[test]
    fn repeated_growth_keeps_cross_region_cycles_and_weak_cleanup() {
        let mut heap = Heap::new(1, 64);
        let mut oldest = ptr::null_mut();
        for index in 0..12 {
            let value = heap.object(BLOCK_SIZE - 8, 6, heap.frame.values[0]);
            unsafe {
                *value.add(2) = index as u64;
            }
            heap.frame.values[0] = value as u64;
            if index == 0 {
                oldest = value;
            }
            heap.watch(value, index);
        }
        assert_eq!(
            (heap.collector.regions.len(), heap.collector.heap_bytes),
            (5, 16 * BLOCK_SIZE)
        );
        let count = 131072;
        let array = heap.object(16 + count * 8, 15, count as u64);
        unsafe {
            *array.add(count + 1) = heap.frame.values[0];
            *oldest.add(1) = array as u64;
        }
        heap.watch(array, 12);
        heap.collect();
        assert_eq!(
            (heap.collector.regions.len(), heap.collector.heap_bytes),
            (6, 49 * BLOCK_SIZE)
        );
        let mut value = heap.frame.values[0] as *mut u64;
        for index in (0..12).rev() {
            unsafe {
                assert_eq!(*value.add(2), index as u64);
                value = *value.add(1) as *mut u64;
            }
        }
        assert_eq!(value, array);
        assert_eq!(&heap.finalized[..13], &[0; 13]);
        heap.frame.values[0] = 0;
        heap.collect();
        assert_eq!(&heap.finalized[..13], &[1; 13]);
        assert_eq!(heap.object(16 + count * 8, 15, count as u64), array);
        heap.collect();
        assert_eq!(&heap.finalized[..13], &[1; 13]);
    }

    #[test]
    fn a_large_allocation_in_another_region_keeps_the_small_bumps_owner() {
        let mut heap = Heap::new(4, 16);
        let first = heap.object(24, 10, 123);
        heap.frame.values[0] = first as u64;
        heap.frame.values[1] = heap.object(3 * BLOCK_SIZE - 8, 10, 456) as u64;
        heap.frame.values[2] = heap.object(4 * BLOCK_SIZE - 8, 10, 789) as u64;
        assert_eq!(
            (heap.collector.regions.len(), heap.collector.heap_bytes),
            (2, 8 * BLOCK_SIZE)
        );
        heap.frame.values[1..3].fill(0);
        heap.collect();
        heap.frame.values[2] = heap.object(3 * BLOCK_SIZE - 8, 10, 456) as u64;
        let small = heap.object(24, 10, 987);
        heap.frame.values[1] = small as u64;
        let collections = heap.collector.collections();
        let large = heap.object(3 * BLOCK_SIZE - 8, 10, 654);
        heap.frame.values[3] = large as u64;
        let tail = heap.object(24, 10, 321);
        heap.frame.values[4] = tail as u64;
        assert_eq!(tail, unsafe { small.add(4) });
        assert_eq!(heap.collector.collections(), collections);
        heap.collect();
        unsafe {
            assert_eq!(
                (*first.add(1), *small.add(1), *large.add(1), *tail.add(1)),
                (123, 987, 654, 321)
            );
        }
    }

    #[test]
    fn fake_interior_headers_stale_slots_and_immediates_do_not_retain_objects() {
        let mut heap = Heap::new(1, 2);
        let owner = heap.object(48, 10, (16 << 2) | 1);
        unsafe {
            *owner.add(2) = u64::MAX;
        }
        heap.frame.values[0] = owner as u64;
        heap.frame.values[1] = unsafe { owner.add(2) } as u64;
        heap.watch(owner, 0);
        heap.collect();
        assert_eq!(heap.finalized[0], 0);
        heap.frame.values[0] = 1;
        heap.frame.values[2] = owner as u64;
        heap.frame.header.count = 2;
        heap.collect();
        assert_eq!(heap.finalized[0], 1);
        assert_eq!(heap.collector.stats.live_objects, 0);
        // Republish the reclaimed exact address before any storage is reused.
        // Its old header cannot authorize a root after start membership clears.
        heap.frame.header.count = 3;
        heap.collect();
        assert_eq!(heap.collector.stats.live_objects, 0);
        assert_eq!(heap.finalized[0], 1);
        heap.frame.header.count = 2;
        let child = heap.object(24, 10, 111);
        heap.watch(child, 1);
        let numeric = heap.object(24, 10, child as u64);
        heap.frame.values[0] = numeric as u64;
        heap.collect();
        assert_eq!(heap.finalized[1], 1);
        unsafe {
            assert_eq!(*numeric.add(1), child as u64);
        }
    }

    #[test]
    fn bounded_growth_collects_and_reuses_before_exhaustion() {
        let mut heap = Heap::new(1, 10);
        for index in 0..10 {
            heap.frame.values[index] = heap.object(BLOCK_SIZE - 8, 10, index as u64) as u64;
        }
        assert_eq!(
            (heap.collector.regions.len(), heap.collector.heap_bytes),
            (5, 10 * BLOCK_SIZE)
        );
        let collections = heap.collector.collections();
        let attempts = heap.collector.allocation_failures.attempts;
        assert!(heap.allocate(24).is_null());
        assert_eq!(heap.collector.collections(), collections + 1);
        assert_eq!(heap.collector.allocation_failures.attempts, attempts);
        for index in 0..10 {
            unsafe {
                assert_eq!(*(heap.frame.values[index] as *mut u64).add(1), index as u64);
            }
        }
        heap.frame.values[3] = 0;
        heap.frame.values[3] = heap.object(BLOCK_SIZE - 8, 10, 42) as u64;
        assert_eq!(heap.collector.heap_bytes, 10 * BLOCK_SIZE);
    }

    #[test]
    fn failed_metadata_and_mapping_growth_leave_existing_regions_intact() {
        let mut heap = Heap::new(1, 10);
        heap.frame.values[0] = heap.object(BLOCK_SIZE - 8, 10, 123) as u64;
        heap.collector.allocation_failures.metadata = true;
        assert!(heap.allocate(24).is_null());
        heap.collector.allocation_failures.metadata = false;
        heap.collector.allocation_failures.mapping = true;
        assert!(heap.allocate(24).is_null());
        heap.collector.allocation_failures.mapping = false;
        assert_eq!(
            (heap.collector.regions.len(), heap.collector.heap_bytes),
            (1, BLOCK_SIZE)
        );
        heap.frame.values[1] = heap.object(BLOCK_SIZE - 8, 10, 456) as u64;
        heap.collector.allocation_failures.mapping_limit = BLOCK_SIZE;
        let attempts = heap.collector.allocation_failures.attempts;
        heap.frame.values[2] = heap.object(BLOCK_SIZE - 8, 10, 789) as u64;
        assert_eq!(heap.collector.allocation_failures.attempts, attempts + 2);
        assert_eq!(heap.collector.heap_bytes, 3 * BLOCK_SIZE);
        heap.collect();
        for (index, value) in [123, 456, 789].into_iter().enumerate() {
            unsafe {
                assert_eq!(*(heap.frame.values[index] as *mut u64).add(1), value);
            }
        }
    }

    #[test]
    fn impossible_sizes_do_not_collect_or_attempt_growth() {
        let mut heap = Heap::new(1, 4);
        let attempts = heap.collector.allocation_failures.attempts;
        for bytes in [usize::MAX, usize::MAX / 4, usize::MAX / 4 + 1] {
            assert!(heap.allocate(bytes).is_null());
        }
        assert_eq!(heap.collector.collections(), 0);
        assert_eq!(heap.collector.allocation_failures.attempts, attempts);
        heap.collector.budget = BLOCK_SIZE;
        heap.collector.config.minimum_budget = BLOCK_SIZE;
        heap.frame.values[0] = heap.object(BLOCK_SIZE - 8, 10, 123) as u64;
        heap.frame.values[1] = heap.object(BLOCK_SIZE - 8, 10, 456) as u64;
        assert_eq!(heap.collector.collections(), 1);
        assert_eq!(heap.collector.regions.len(), 2);
    }

    #[test]
    fn capacity_misses_seek_headroom_but_can_reuse_when_growth_fails() {
        for (retained, maximum, fail, mappings) in [
            (896, 8, false, 2),
            (768, 8, false, 1),
            (896, 8, true, 1),
            (896, 4, false, 1),
        ] {
            let mut heap = Heap::new(4, maximum);
            for index in 0..1024 {
                let value = heap.object(120, 6, heap.frame.values[0]);
                if index < retained {
                    heap.frame.values[0] = value as u64;
                }
            }
            heap.collector.allocation_failures.mapping = fail;
            let mut value = heap.object(24, 6, heap.frame.values[0]);
            heap.frame.values[0] = value as u64;
            heap.collector.allocation_failures.mapping = false;
            assert_eq!(heap.collector.collections(), 1);
            assert_eq!(heap.collector.regions.len(), mappings);
            heap.collect();
            for _ in 0..retained {
                unsafe {
                    value = *value.add(1) as *mut u64;
                    assert_eq!(*value, 6);
                }
            }
            unsafe {
                assert_eq!(*value.add(1), 0);
            }
        }
    }

    #[test]
    fn large_reserved_tails_count_toward_headroom() {
        let mut heap = Heap::new(4, 8);
        heap.frame.values[0] = heap.object(2 * BLOCK_SIZE, 10, 123) as u64;
        heap.frame.values[1] = heap.object(120, 10, 456) as u64;
        for index in 1..256 {
            heap.object(120, 10, index);
        }
        heap.frame.values[2] = heap.object(24, 10, 789) as u64;
        assert_eq!(heap.collector.collections(), 1);
        assert_eq!(heap.collector.regions.len(), 2);
        heap.collect();
        unsafe {
            assert_eq!(*(heap.frame.values[0] as *mut u64).add(1), 123);
            assert_eq!(*(heap.frame.values[1] as *mut u64).add(1), 456);
        }
    }

    #[test]
    fn byte_configuration_rejects_invalid_zero_and_overflow() {
        for text in ["", "0", "-1", "12x", "12 ", "18446744073709551616"] {
            assert_eq!(parse_bytes(text), None);
        }
        assert_eq!(parse_bytes("+32768"), Some(32768));
        assert_eq!(parse_bytes(" 32768"), Some(32768));
        assert_eq!(parse_bytes("262144"), Some(262144));
    }
}
