# Roadmap

Lofi compiles to WasmGC and runs on V8. Chibi hosts the compiler. The
[language book](book/lofi/index.md) defines the target language; the
[tour](../TOUR.md) describes the implementation. Open items are tracked in
[TODO.md](../TODO.md).

## Implemented

- Located syntax → resolved IR → inference → concrete specialization → WasmGC,
  with Binaryen optimization and Rust scalar services linked as Wasm.
- Rank-one `All` with `requires` clauses, nominal `data`, typeclasses with
  concrete instance heads, typed externs and fixed-arity overload families.
- `define-library` with explicit library maps, hygienic `syntax-rules`, and an
  initial typed `(scheme base)` written as macros over the Lofi kernel.
- Fixed-arity functions; collection packing macros expand to list workers.
- Wrapping I32/I64 and IEEE F32/F64 arithmetic; checked literal construction
  and narrowing conversions.
- Derived `Serialize`/`Deserialize` instances over finite S-expressions with
  readable text and compact binary encodings.
- Source-level `generate-library` recipes with separate producer and
  application dependency maps.

## Next

- Keep WasmGC as the execution target. Broaden typed host interfaces with an
  explicit ABI and execution checks.
- Add constrained generic instances, so parameterized types such as options can
  derive serialization.
- Revisit platform effects, actors and heterogeneous targets on typed Lofi
  interfaces.
- Add source mappings from emitted code back to located Lofi.
- Extend Scheme beyond the typed subset and specify procedural transformers.
- Compile the compiler through its own pipeline, then retire Chibi at a
  separate self-hosting milestone.
