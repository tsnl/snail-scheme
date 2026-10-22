# Toolchain: linking, live reload and the browser

> **Status: proposed.** Section 4.1 describes the whole-program live reload
> of `lofi serve` and `lofi watch`, implemented in #367 and not yet merged.
> Everything else here is a design, and section 9 lists what is still
> undecided.

This document plans how Lofi programs are built, linked, reloaded and
loaded during development, so that a rebuild costs as much as the edit
that caused it and the same toolchain can run in a browser. C is the
reference model: programs are statically linked, a debug build may link
dynamically, and code loaded at run time is reached through explicit,
unchecked casts.

## 1. Goals

1. Rebuild and reload in proportion to the edit, not to the program.
2. Hot reload at the granularity of a module, keeping the application's
   state.
3. Notebooks of compiled, typed cells that rerun without a manual order
   (#368).
4. One toolchain for Lofi and for the Scheme that `(scheme compiler)`
   translates into Lofi.
5. The development loop written in Lofi and Rust, with hosts that only
   perform I/O.
6. The whole debug toolchain running in a browser.

## 2. Where a rebuild's time goes

A rebuild of Siegework through `lofi serve` takes about 1.4 seconds:

| Step | Time |
| --- | --- |
| Starting Chibi and loading the driver, `(lofi build)` | 345 ms |
| Compiling to WebAssembly text with the compiled compiler | 463 ms |
| Optimizing twice with `wasm-opt` | 170 ms |
| Assembling with `wasm-as` and merging the runtime with `wasm-merge` | 170 ms |
| Starting Node | 26 ms |

Half of it is work that a debug build need not do: starting Chibi, and
optimizing. The compile itself is whole-program, so an edit to one library
checks and emits every library again.

## 3. Linking, after C

| Build | Linking |
| --- | --- |
| Release | Static. The whole program is compiled at once, optimized and tree-shaken, and the Rust runtime is merged in. This is today's build. |
| Debug | Dynamic. Each library is compiled separately to its own module, and the modules are linked when the program is instantiated. The Rust runtime is a separate instance, like a shared C library. Nothing is optimized or tree-shaken. |
| Either | Code loaded while the program runs, through `(lofi wasm)` (section 3.3). |

### 3.1 Separate compilation

The unit of compilation is a library. The compiler, running for as long as
the development loop does, keeps each library's **interface** in memory:

- the type scheme of each export, with its effect row;
- its data types, with the recursion group that holds their WasmGC types;
- its classes and instances;
- its macros, which expand in the importing library;
- the checked bodies of its generic definitions, which the importing library
  monomorphizes at its own types, as C++ templates live in headers.

A library is checked statically against the interfaces of the libraries it
imports, then compiled to a module. An interface has a hash. An edit
recompiles its library, and recompiles the libraries that import it only if
the hash changed, as GHC avoids recompilation. Two modules may instantiate
the same generic definition at the same types; in a debug build each keeps
its own copy.

The cache lives in memory, for as long as the compiler runs. For each
library it holds the assembled binary module, the interface and the
interface's hash, keyed by a hash of the library's source, the interface
hashes of its imports, and the compiler's identity. Imported macros and
generic bodies end up inside a module, so their interfaces are part of the
key. A body edit misses for one library: it is compiled, assembled and
swapped, and every other module is reused, along with the engine's
compiled form of it. A cold start builds everything once. Keeping the cache
on disk is left for later (section 9).

### 3.2 Dynamic linking

A module reaches each export of another library through a mutable global
that holds it, as an ELF program reaches a shared library through its
global offset table. The loader instantiates modules in dependency order
and fills those globals. A call across libraries costs one indirect call,
in debug builds only.

WebAssembly treats two GC types as the same only when their whole
recursion groups match. A spike in Node showed that a module importing a
function over a struct links when it repeats the exporting module's whole
recursion group, keeps two identically shaped types in that group
distinct, and fails to link if it declares the struct in a group of its
own. So each library's data types form one recursion group, and every
module that uses them repeats it exactly.

There are two places where types are checked:

- **At compile time,** each library against the interfaces it imports.
- **At load time,** once per import: the loader compares the interface hash
  that the importer was compiled against with the one the exporter has,
  as C++ mangles types into names and OCaml records interface digests.
  The engine also checks the WebAssembly types of every import, but those
  are coarser than Lofi's: effect rows and aliases are erased, and two enums
  without fields are both `i32`.

Calls never check. A value that crosses as `Any` keeps its own check at
`type-convert`.

### 3.3 Loading modules at run time

`(lofi wasm)` is `dlopen`: it loads a module from bytes with the imports
given, and returns its exports, which the caller casts to the types it
expects.

```scheme
(let* ((cell (load-module bytes imports))
       (run (unsafe-cast (module-export cell "run") (-> I64 I64))))
  (run 41))
```

`unsafe-cast` checks nothing about Lofi types, so the unsafe assumption is
visible where it is made; the engine still traps on a structural mismatch.
To exchange GC values with its host, a loaded module repeats the host's
recursion groups (section 3.2). Its uses are notebook cells, plugins, and
`generate-library` producers, which then run in the compiler's own process
instead of in a separate program.

## 4. Hot reload

### 4.1 Swapping the program (#367)

`lofi serve` rebuilds the whole program and swaps the new module into each
open page. The running module's save is restored into the new one, the
contract a page reload already uses, so an application whose save is a
journal, as Siegework's is, replays it under the new code. A failed build
or a save the new module cannot restore leaves the old module running.

### 4.2 Swapping a module

With dynamic linking, a swap replaces only the rebuilt modules. Between two
events, the loader instantiates each new module and points the globals that
reach its exports at it; the modules that import it are not touched.

**Module globals are ephemeral.** A swapped module runs its top level
again, and whatever its globals held is rebuilt from nothing. The one value
that survives is the application's state. `define-application` gives it to
the loader before the swap and takes it back after, so it crosses even when
the module holding it is swapped:

- by reference, when none of the data types it contains changed, because
  their recursion groups are identical and the new code accepts the old
  values as they are;
- through `save` and `restore`, as in section 4.1, when they did.

Treating globals as ephemeral, rather than requiring modules without state,
is deliberate. `(scheme compiler)` translates every top-level Scheme
variable into a cell, so a Scheme library is stateful by construction, and
any test that rejected stateful modules would reject all Scheme. A swapped
Scheme library simply runs again, as it would when first loaded.

| Edit | Rebuilt | Swapped | State |
| --- | --- | --- | --- |
| A function body | That library | That module | Kept as is |
| An interface, with data types unchanged | That library and its importers | Those modules | Kept as is |
| A data type | That library and every user of the type | Those modules | Through `save` and `restore` |
| The host's scripts or page | Nothing | The page reloads | Through `save` and `restore` |

Three hazards remain:

- A closure stored in the state keeps running the code it was made from
  until the state is rebuilt. An application that stores functions in its
  state should swap through `save` and `restore`.
- A swap happens only between events. Effect handlers are installed only
  while a call runs, so between events no handler is active and no frame of
  the old code is on the stack.
- A module that traps stops the clock with the state from before the trap,
  and the next good swap resumes it, as section 4.1 does now.

## 5. The development loop in Lofi

The loop's decisions form a total state machine, written like a
`(lofi app)`. Its events are sources changing, a build finishing and a page
connecting; its commands are starting a build and sending a page the
manifest of the build being served. Debouncing, one build at a time,
manifests and the choice between swapping a module, restyling and reloading
the page all live there, and can be tested with programs and checked with
`(lofi explore)`, for example that at most one build runs and that a page
never applies an older build after a newer one.

The reload client in a page is a small Lofi module that makes the same
choices from manifests. Hosts carry I/O only:

- **In a browser,** JavaScript binds the DOM, WebGPU, `WebAssembly` and
  event streams, which WebAssembly cannot reach directly, and decides
  nothing.
- **On a server,** either Node binds HTTP, file watching and timers, or a
  native Rust host embedding wasmtime does, without JavaScript.

## 6. Scheme

A Scheme program becomes a Lofi library through `(scheme compiler)`, so it
is compiled separately, linked and swapped like any other library. Every
Scheme variable is a cell, and a swapped Scheme library runs its top level
again. Scheme's REPL expects that redefining a procedure changes what every
caller calls, and the mutable globals of section 3.2 give a library's
exports that meaning.

## 7. The toolchain in a browser

| Piece | In a browser |
| --- | --- |
| Compiler | Already WebAssembly. It reads `lib/` and the project from a file system kept in memory, which the Rust runtime can provide. |
| Assembler | Binary emitted directly from the compiler's WebAssembly text forms, instead of through `wasm-as`. This is the one large new component. |
| Linker | The loader of section 3.2; a debug build merges nothing. |
| Runtime | The prebuilt `snail_runtime.wasm`, instantiated once. |
| Optimizer | None for debug builds. For release builds, Binaryen compiled to WebAssembly, if a spike shows its threads and exceptions can be tamed, or no optimizer. |
| Loop | The state machine of section 5 in a worker, driven by an editor's events instead of file watching and HTTP. |

## 8. Order of work

Each step is useful alone.

1. Debug builds skip `wasm-opt` and instantiate the runtime separately.
2. The development loop and the reload client in Lofi, on thin hosts.
3. A long-lived compiler: separate compilation with interfaces in memory,
   and the dynamic linking of section 3.2.
4. Swapping modules (section 4.2), keeping section 4.1 as the fallback.
5. Binary emission.
6. The toolchain in a browser worker.
7. `(lofi wasm)`, for notebook cells (#368), plugins and producers.
8. If wanted, release optimization in a browser.

## 9. Open questions

- **The server's host:** Node with thin bindings, or a native Rust host
  embedding wasmtime, whose support for WebAssembly GC is younger.
- **Load-time checks:** made by the loader, from hashes each module records,
  or by code each module runs when it starts.
- **Closures in the state:** whether to detect them from the state's type
  and fall back to `save` and `restore` automatically.

Left for later, if a cold start or one-shot commands become too slow:

- **The cache on disk.** Entries keyed by content hashes and written
  atomically, so parallel builds cannot collide. A cold start would validate
  them by hashing sources, as Bazel and Nix do, and re-check only the
  dependencies of a library it recompiles.
- **Interfaces as generated headers.** C++ avoids re-parsing headers through
  a binary module interface (Clang's `.pcm`, GCC's `.gcm`) private to the
  compiler; OCaml, GHC and Rust keep similar files. A Lisp can instead print
  each interface as a declaration-only library of S-expressions, whose text
  hash is the interface hash and whose reading needs no format of its own.
  A macro that refers to private helpers would export them as hidden names.
