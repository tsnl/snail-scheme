Run this ordinary build script from the repository root:

```sh
chibi-scheme -I src examples/rust-interop/build.scm
```

The callable Rust functions are in [`src/interop_example.rs`](../../src/interop_example.rs),
compiled into the single standard runtime crate. The build script explicitly
declares their Scheme names and emits `build/rust-interop.wasm`, then runs it.
There is no separate extension crate or package discovery step. Future extension
packaging is deferred while the runtime and library APIs settle.

Import `(snail-scheme extensions)` to access the declared Scheme names. Each
function is exported as `snail:<Scheme-name>` and receives a borrowed argument
vector handle. The function returns an independently owned result handle.
`Arguments::get` and `Root::clone` create owned roots; `Root::drop` releases them;
`Root::into_handle` transfers ownership to Scheme. Rust code can retain a `Root`
between calls without knowing the engine's object layout. `Root::call` invokes
Scheme synchronously with rooted arguments and returns an owned result. The
example exercises a Scheme → Rust → Scheme → Rust callback, a retained pair,
root-table growth, slot reuse, and explicit release of the retained owner.

The example uses `expect` for invalid arguments; a failure terminates execution.
Rust destructors do not run after a Wasm trap. WasmGC itself does not run Rust
destructors; resource cleanup uses the host finalizer hook. Explicitly close
resources when release must happen promptly.
