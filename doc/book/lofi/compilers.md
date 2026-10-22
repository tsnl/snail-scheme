# Compilers as libraries

The compiler is a Lofi program: five passes in `src/lofi/compiler/`, each
consuming the previous pass's output and nothing earlier.

```text
text ──read──▶ located syntax
     ──expand─▶ core program      unique names, resolved types, entity tables
     ──check──▶ typed program     every expression typed, instances chosen
     ──mono───▶ monomorphic program
     ──wasm───▶ WasmGC text ──Binaryen──▶ module, linked with the Rust runtime
```

A release build compiles the whole program at once. A debug build runs
the same passes one library at a time and keeps the results in memory, as
[the development toolchain](toolchain.md) describes.

The passes import only `(lofi base)`, `(lofi table)` and `(lofi io)`, so the
compiler compiles itself. Chibi Scheme runs the same source as the first
stage of the bootstrap, through a host that implements those three
libraries and erases the typed forms; the compiled compiler then rebuilds
itself until it reproduces its own output. Compiling the compiler takes
under a second.

The [compiler tour](https://github.com/tsnl/snail-scheme/blob/main/TOUR.md)
follows a program through each pass, and the
[redesign](https://github.com/tsnl/snail-scheme/blob/main/doc/redesign.md)
records how the compiler came to be shaped this way.
