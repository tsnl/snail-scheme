# Lofi

The Lofi specification now lives in the repository's mdBook. Start with the
[overview and examples](book/lofi/index.md), then read the language before the
library and build model.

## Contents

- [Overview](book/lofi/index.md)
- Language
  - [Terms and definitions](book/lofi/terms.md): expressions, functions, scope,
    bindings, mutation, proper tail recursion and evaluation order.
  - [Types](book/lofi/types.md): primitives, functions, polymorphism, structs,
    unions, classes and subtyping.
  - [Formal summary](book/lofi/reference.md): grammar, typing and evaluation rules.
- [Libraries](book/lofi/libraries.md): source descriptions, exports, imports,
  discovery, generation recipes and the `LofiLibrary` representation.
- [Compilers as libraries](book/lofi/compilers.md): compilation, loading,
  instantiation, generator execution and staging.
- [Notable omissions](book/lofi/omissions.md)
- [Implementation extensions](book/lofi/extensions.md)
- [References](book/lofi/references.md)

## Reading locally

```sh
nix-shell
scripts/book serve --hostname 127.0.0.1 --port 8000
```

Open <http://127.0.0.1:8000/lofi/>. The book reloads as its sources change.
`scripts/book build` writes the rendered book to `build/book/`.

These chapters specify the language and library contracts. The current compiler
has Chibi-hosted APIs that parse dependency-independent library values, resolve
explicit library maps, and compile a public `Entry` to a Wasm or native64
artifact. Entries currently use the existing monomorphic scalar function ABI;
provider linking is separate. A JavaScript Wasm adapter loads those artifact
bytes, creates independent instances with typed providers and checks scalar
entry calls. The [Scheme native adapter](lofi-native-loading.md) separately links
providers and creates independent native instances with checked scalar transport.
The [Lofi builder](lofi-builder.md) constructs and inspects the full
library syntax and transfers owned data into Chibi; the source driver executes
explicit [generation recipes](lofi-generation.md). Ordinary Lofi programs can
also call the [compiler and Wasm execution service](lofi-compiler-service.md),
with explicit library maps and recoverable error values. Its `parse-library`
returns inspectable, transformable `LofiLibrary` data through the same builder
views and constructors. Native target support in that Lofi service remains
pending. See [the compiler tour](../TOUR.md) for
module responsibilities.
