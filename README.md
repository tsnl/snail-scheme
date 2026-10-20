# Lofi

Lofi is a typed functional language with Scheme syntax that compiles to
WasmGC. It has structs, enums, pattern matching, typeclasses with generic
instances, Koka-style effect rows with handlers, and wire types with stable
schema identities. The compiler is written in Lofi and compiles itself; Chibi
Scheme runs its source to start the first bootstrap.

```scheme
(import
 (lofi base)
 (lofi io))

(: fibonacci (-> I64 I64))
(define (fibonacci n)
  (if (< n 2) n (+ (fibonacci (- n 1)) (fibonacci (- n 2)))))

(display (fibonacci 30))
(newline)
```

## Getting started

```sh
nix-shell
rustup target add wasm32-wasip1
./lofi run examples/fibonacci.sld
./lofi compile -o fibonacci.wasm examples/fibonacci.sld
./lofi wat examples/effects.sld
```

Chibi Scheme, Binaryen, Cargo and Node are required; `shell.nix` provides
them. Programs are linked with a small Rust runtime and run under WASI.

## Siegework

[Siegework](apps/siegework) is a small colony game written in Lofi: explore a
seeded map, mine ore, and destroy three nests before their waves destroy
your hub. It runs in the browser with WebGPU.

```sh
make site
python3 -m http.server 4191 --directory build/siegework
```

## Reading on

- [The language guide](doc/language.md) describes the language as implemented.
- [The compiler tour](TOUR.md) follows a program through the passes.
- [The redesign](doc/redesign.md) records the design and what remains.

[Apache-2.0](LICENSE)
