# References

- [R7RS](https://small.r7rs.org/), the Scheme standard whose syntax and
  libraries Snail Scheme follows.
- [WebAssembly garbage collection](https://github.com/WebAssembly/gc), the
  target: structs, arrays and references managed by the engine.
- [wasm-tools](https://github.com/bytecodealliance/wasm-tools), whose `wat`
  crate assembles the compiler's output, and
  [wasm-fuse](https://crates.io/crates/wasm-fuse), which links the scalar runtime.
- Luc Maranget, *Compiling Pattern Matching to Good Decision Trees* and
  *Warnings for Pattern Matching*: the checks behind `match`.
- Per Vognsen's [Bitwise](https://github.com/pervognsen/bitwise) and Resin's
  [discussion of it](https://github.com/tsnl/resin/blob/main/doc/bitwise.md):
  representations that explain operations, and control flow that teaches
  the problem.
- [Chez Scheme](https://github.com/cisco/ChezScheme), the first stage of
  the compiler's bootstrap.
