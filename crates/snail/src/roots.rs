//! Shadow frames obey the Wasm call stack. A trap skips generated epilogues, so
//! a host invocation restores the depth it found before entering managed code.

use wasmtime::{AsContextMut, Instance, TypedFunc};

pub struct Checkpoint {
    restore: Option<TypedFunc<i32, ()>>,
    depth: i32,
}

impl Checkpoint {
    pub fn capture(mut store: impl AsContextMut, instance: &Instance) -> wasmtime::Result<Self> {
        let Some(read) = instance.get_func(&mut store, "snail:gc/checkpoint") else {
            return Ok(Self {
                restore: None,
                depth: 0,
            });
        };
        let depth = read.typed::<(), i32>(&store)?.call(&mut store, ())?;
        let restore = Some(instance.get_typed_func(&mut store, "snail:gc/restore")?);
        Ok(Self { restore, depth })
    }

    pub fn restore(self, store: impl AsContextMut) -> wasmtime::Result<()> {
        if let Some(restore) = self.restore {
            restore.call(store, self.depth)?;
        }
        Ok(())
    }
}
