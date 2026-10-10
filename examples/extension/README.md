Run from the repository root:

```sh
./snail-scheme examples/extension.scm --extension examples/extension
./snail-scheme examples/extension.scm --extension examples/extension -o extension.wasm
```

The driver reads `package.metadata.snail.exports`, adds this Rust crate and the
runtime as dependencies of a generated Cargo `cdylib`, and builds it for
`wasm32-wasip1`. That Wasm module links with the Scheme module through the AWI.
The final artifact contains one Rust linear memory. No native Rust linking is
required to execute it.

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
