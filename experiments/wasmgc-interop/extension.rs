#![no_std]

// ---- Imported Scheme operations ----

// These are ordinary wasm32 C ABI calls, wired directly to Wasm exports.
// A handle indexes a GC reference table; it is never a GC object's address.
#[link(wasm_import_module = "scheme")]
unsafe extern "C" {
    fn retain(handle: u32) -> u32;
    fn release(handle: u32);
    fn first(handle: u32) -> i32;
    fn second(handle: u32) -> i32;
    fn make_pair(first: i32, second: i32) -> u32;
}

// ---- Owned roots ----

// One Root owns one table slot. Dropping it releases that root; the engine
// subsequently decides when to collect the object. Rust never runs its GC.
struct Root(u32);

impl Root {
    fn retain(handle: u32) -> Self {
        Self(unsafe { retain(handle) })
    }

    fn into_handle(self) -> u32 {
        let handle = self.0;
        core::mem::forget(self);
        handle
    }
}

impl Drop for Root {
    fn drop(&mut self) {
        unsafe { release(self.0) }
    }
}

static mut SAVED: Option<Root> = None;

fn replace_saved(root: Option<Root>) {
    // This single-threaded prototype moves the previous owner out before Drop.
    // No reference into the static survives the imported release call.
    drop(unsafe { core::ptr::addr_of_mut!(SAVED).replace(root) });
}

// ---- Callable extension functions ----

#[unsafe(no_mangle)]
pub extern "C" fn pair_sum(handle: u32, increment: i32) -> i32 {
    unsafe { first(handle) + second(handle) + increment }
}

#[unsafe(no_mangle)]
pub extern "C" fn save_pair(handle: u32) -> u32 {
    let root = Root::retain(handle);
    let retained = root.0;
    replace_saved(Some(root));
    retained
}

#[unsafe(no_mangle)]
pub extern "C" fn clear_saved_pair() {
    replace_saved(None);
}

#[unsafe(no_mangle)]
pub extern "C" fn shifted_pair(handle: u32, increment: i32) -> u32 {
    let first = unsafe { first(handle) } + increment;
    let second = unsafe { second(handle) } + increment;
    // Transfer the new root to Scheme. The caller must release the table slot
    // after taking the reference, or retain ownership if keeping this handle.
    Root(unsafe { make_pair(first, second) }).into_handle()
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo<'_>) -> ! {
    core::arch::wasm32::unreachable()
}
