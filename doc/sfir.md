# SFIR

The SFIR specification now lives in the repository's mdBook. Start with the
[overview and examples](book/sfir/index.md), then read the language before the
library and build model.

## Contents

- [Overview](book/sfir/index.md)
- Language
  - [Terms and definitions](book/sfir/terms.md): expressions, functions, scope,
    bindings, mutation, proper tail recursion and evaluation order.
  - [Types](book/sfir/types.md): primitives, functions, polymorphism, structs,
    unions, classes and subtyping.
  - [Formal summary](book/sfir/reference.md): grammar, typing and evaluation rules.
- [Libraries](book/sfir/libraries.md): source descriptions, exports, imports,
  discovery, generation recipes and the `SfirLibrary` representation.
- [Compilers as libraries](book/sfir/compilers.md): compilation, loading,
  instantiation, generator execution and staging.
- [Notable omissions](book/sfir/omissions.md)
- [Implementation extensions](book/sfir/extensions.md)
- [References](book/sfir/references.md)

## Reading locally

```sh
nix-shell
scripts/book serve --hostname 127.0.0.1 --port 8000
```

Open <http://127.0.0.1:8000/sfir/>. The book reloads as its sources change.
`scripts/book build` writes the rendered book to `build/book/`.

These chapters specify the language and library contracts. The current compiler
has Chibi-hosted APIs that parse dependency-independent library values, resolve
explicit library maps, and compile a public `Entry` to a Wasm or native64
artifact. Entries currently use the existing monomorphic scalar function ABI;
provider linking is separate. A JavaScript Wasm adapter loads those artifact
bytes, creates independent instances with typed providers and checks scalar
entry calls. The [Python native adapter](sfir-native-loading.md) separately links
providers and creates independent native instances with checked scalar transport.
The [SFIR builder](sfir-builder.md) constructs and inspects the full
library syntax and transfers owned data into Chibi; the source driver executes
explicit [generation recipes](sfir-generation.md). Ordinary SFIR programs can
also call the [compiler and Wasm execution service](sfir-compiler-service.md),
with explicit library maps and recoverable error values. Native target support
in that SFIR service and first-class parsing that returns inspectable
`SfirLibrary` data to SFIR remain pending; service source insertion currently
parses directly into its owned map. See [the compiler tour](../TOUR.md) for
module responsibilities.
