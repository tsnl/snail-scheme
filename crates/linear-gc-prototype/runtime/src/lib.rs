//! Bounded, nonmoving mark/line prototype, informed by fc8bf59a's Immix.
//! All storage, including metadata and explicit roots, is in linear memory.
//! No implicit Rust/Wasm local is a root. Collection only happens in alloc or
//! collect; callers publish every live address before entering either.
#![no_std]
#![allow(static_mut_refs)]
#![cfg_attr(target_arch = "wasm64", feature(simd_wasm64))]

use core::{mem::size_of, ptr};

// ---- Heap representation ----

const BLOCK: usize = 32768;
const LINE: usize = 128;
const ALIGN: usize = 16;
const HEAP: usize = 4 * 1024 * 1024;
const SLOTS: usize = HEAP / ALIGN;
const WORD: usize = size_of::<usize>();
const ROOTS: usize = 8192;

#[repr(C, align(32768))]
struct Arena([u8; HEAP]);

static mut ARENA: Arena = Arena([0; HEAP]);
static mut ROOT: [usize; ROOTS] = [0; ROOTS];
// Each allocation granule identifies its payload start plus one. Membership
// authorizes SIZE/MARK access; an exact byte extent excludes padding/one-past.
static mut OWNER: [u32; SLOTS] = [0; SLOTS];
static mut SIZE: [u32; SLOTS] = [0; SLOTS];
static mut MARK: [u8; SLOTS] = [0; SLOTS];
static mut LINES: [u8; HEAP / LINE] = [0; HEAP / LINE];
static mut WORK: [u32; SLOTS] = [0; SLOTS];
static mut WORK_LEN: usize = 0;
static mut CURSOR: usize = 0;
static mut LIMIT: usize = 0;
static mut SEARCH: usize = 0;
static mut COLLECTIONS: u32 = 0;
static mut LIVE: u32 = 0;
static mut STRESS: u32 = 0;

#[panic_handler]
fn panic(_: &core::panic::PanicInfo<'_>) -> ! {
    #[cfg(target_arch = "wasm32")]
    {
        core::arch::wasm32::unreachable()
    }
    #[cfg(target_arch = "wasm64")]
    {
        core::arch::wasm64::unreachable()
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roots() -> usize {
    (&raw mut ROOT).cast::<usize>() as usize
}

#[unsafe(no_mangle)]
pub extern "C" fn heap_base() -> usize {
    (&raw mut ARENA).cast::<u8>() as usize
}

// ---- Allocation ----

// Claim complete holes, just as the archived allocator does: tracing marks
// live lines; unused tails in claimed holes are unavailable until collection.
unsafe fn claim_hole(bytes: usize) -> bool {
    unsafe {
        while SEARCH < LINES.len() {
            let first = SEARCH;
            let end = ((first / (BLOCK / LINE)) + 1) * (BLOCK / LINE);
            if LINES[first] != 0 {
                SEARCH += 1;
                continue;
            }
            while SEARCH < end && LINES[SEARCH] == 0 {
                SEARCH += 1;
            }
            if (SEARCH - first) * LINE < bytes {
                continue;
            }
            LINES[first..SEARCH].fill(1);
            CURSOR = first * LINE;
            LIMIT = SEARCH * LINE;
            return true;
        }
        false
    }
}

unsafe fn reserve(bytes: usize) -> usize {
    unsafe {
        if CURSOR + bytes > LIMIT && !claim_hole(bytes) {
            return usize::MAX;
        }
        let start = CURSOR;
        CURSOR += bytes;
        start
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn alloc(bytes: usize, root_end: usize) -> usize {
    unsafe {
        // This deliberately bounded prototype omits Immix's large-object path.
        assert!(bytes > 0 && bytes <= BLOCK);
        let rounded = (bytes + ALIGN - 1) & !(ALIGN - 1);
        let mut start = reserve(rounded);
        if start == usize::MAX {
            collect(root_end);
            start = reserve(rounded);
        }
        assert!(start != usize::MAX, "bounded heap exhausted");
        OWNER[start / ALIGN..(start + rounded) / ALIGN].fill((start / ALIGN + 1) as u32);
        SIZE[start / ALIGN] = bytes as u32;
        ptr::write_bytes((heap_base() + start) as *mut u8, 0, rounded);
        heap_base() + start
    }
}

// ---- Conservative tracing ----

unsafe fn candidate(value: usize) -> Option<usize> {
    unsafe {
        let offset = value.wrapping_sub(heap_base());
        if offset >= HEAP {
            return None;
        }
        let owner = OWNER[offset / ALIGN];
        if owner == 0 {
            return None;
        }
        let slot = owner as usize - 1;
        (offset - slot * ALIGN < SIZE[slot] as usize).then_some(slot)
    }
}

unsafe fn mark(value: usize) {
    unsafe {
        if let Some(slot) = candidate(value) {
            if MARK[slot] != 0 {
                return;
            }
            MARK[slot] = 1;
            WORK[WORK_LEN] = slot as u32;
            WORK_LEN += 1;
        }
    }
}

unsafe fn trace() {
    unsafe {
        while WORK_LEN != 0 {
            WORK_LEN -= 1;
            let slot = WORK[WORK_LEN] as usize;
            let start = slot * ALIGN;
            let bytes = SIZE[slot] as usize;
            LINES[start / LINE..(start + bytes).div_ceil(LINE)].fill(1);
            for offset in (0..bytes / WORD * WORD).step_by(WORD) {
                mark(ptr::read((heap_base() + start + offset) as *const usize));
            }
        }
    }
}

unsafe fn sweep() {
    unsafe {
        LIVE = 0;
        for slot in 0..SLOTS {
            if SIZE[slot] == 0 {
                continue;
            }
            if MARK[slot] != 0 {
                LIVE += 1;
                continue;
            }
            let granules = (SIZE[slot] as usize).div_ceil(ALIGN);
            OWNER[slot..slot + granules].fill(0);
            SIZE[slot] = 0;
        }
        CURSOR = 0;
        LIMIT = 0;
        SEARCH = 0;
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn collect(root_end: usize) {
    unsafe {
        assert!(root_end >= roots() && root_end <= roots() + ROOTS * WORD);
        assert!((root_end - roots()) % WORD == 0);
        MARK.fill(0);
        LINES.fill(0);
        WORK_LEN = 0;
        for index in 0..(root_end - roots()) / WORD {
            mark(ROOT[index]);
        }
        trace();
        sweep();
        COLLECTIONS += 1;
    }
}

// ---- Experiment controls ----

#[unsafe(no_mangle)]
pub unsafe extern "C" fn stress(enabled: u32) {
    unsafe {
        STRESS = enabled;
    }
}

// This imported call is the same in all timing arms. Keep its collection
// decision in the runtime module so the workload cannot prove it noncollecting.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn safepoint(root_end: usize) {
    unsafe {
        if STRESS != 0 {
            collect(root_end);
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn reset() {
    unsafe {
        OWNER.fill(0);
        SIZE.fill(0);
        MARK.fill(0);
        LINES.fill(0);
        ROOT.fill(0);
        WORK_LEN = 0;
        CURSOR = 0;
        LIMIT = 0;
        SEARCH = 0;
        COLLECTIONS = 0;
        LIVE = 0;
        STRESS = 0;
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn collections() -> u32 {
    unsafe { COLLECTIONS }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn live() -> u32 {
    unsafe { LIVE }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn contains(value: usize) -> u32 {
    unsafe { candidate(value).is_some() as u32 }
}
