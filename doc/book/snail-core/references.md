# References

- [R7RS](https://small.r7rs.org/), the Scheme standard whose syntax and
  libraries Snail-Core follows.
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
- [Chibi Scheme](https://github.com/ashinn/chibi-scheme), the first stage of
  the compiler's bootstrap.
