//! Example callable Rust functions, compiled into the standard Wasm runtime.
//! Roots can outlive a call. Dropping the owner releases its WasmGC table slot.

use crate::awi::{Arguments, Root};
use std::cell::RefCell;

// ---- AWI exports ----

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:rust-triple"))]
pub extern "C" fn triple(raw: u32) -> u32 {
    let args = unsafe { Arguments::borrow(raw) };
    args.check("rust-triple", 1, 1).expect("one argument");
    let value = args.get(0).unwrap().as_integer().expect("an integer");
    Root::integer(value.checked_mul(3).expect("integer overflow")).into_handle()
}

thread_local! { static REMEMBERED: RefCell<Option<Root>> = const { RefCell::new(None) }; }

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:rust-remember"))]
pub extern "C" fn remember(raw: u32) -> u32 {
    let args = unsafe { Arguments::borrow(raw) };
    args.check("rust-remember", 1, 1).expect("one argument");
    REMEMBERED.with_borrow_mut(|slot| *slot = Some(args.get(0).unwrap()));
    Root::unspecified().into_handle()
}

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:rust-recalled"))]
pub extern "C" fn recalled(raw: u32) -> u32 {
    let args = unsafe { Arguments::borrow(raw) };
    args.check("rust-recalled", 0, 0).expect("no arguments");
    REMEMBERED
        .with_borrow(|slot| {
            slot.as_ref()
                .cloned()
                .unwrap_or_else(|| Root::boolean(false))
        })
        .into_handle()
}

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:rust-call"))]
pub extern "C" fn call(raw: u32) -> u32 {
    let args = unsafe { Arguments::borrow(raw) };
    args.check("rust-call", 2, 2)
        .expect("a procedure and an argument");
    let procedure = args.get(0).unwrap();
    let argument = args.get(1).unwrap();
    // Root owners survive reentrancy; no RefCell borrow crosses the callback.
    procedure
        .call(&[argument])
        .expect("Scheme callback")
        .into_handle()
}

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:rust-forget"))]
pub extern "C" fn forget(raw: u32) -> u32 {
    let args = unsafe { Arguments::borrow(raw) };
    args.check("rust-forget", 0, 0).expect("no arguments");
    REMEMBERED.with_borrow_mut(|slot| *slot = None);
    Root::unspecified().into_handle()
}

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:rust-root-stress"))]
pub extern "C" fn root_stress(raw: u32) -> u32 {
    let args = unsafe { Arguments::borrow(raw) };
    args.check("rust-root-stress", 1, 1).expect("one argument");
    let original = args.get(0).unwrap();
    // Force root-table growth, release every slot, and reuse the free slots.
    for _ in 0..2 {
        let roots: Vec<_> = (0..100).map(|_| original.clone()).collect();
        assert!(roots.iter().all(|root| root.same(&original)));
    }
    original.into_handle()
}
