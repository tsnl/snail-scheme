# `snail-scheme`

(WIP)

`snail-scheme` is my personal minimal Scheme implementation.

It offers a nice-to-use C++ API that is easily extended using C++'s native OOP
principles.

It includes a basic interpreter (SSI) written in C++.
- the interpreter is based on Ch4 of ["Three Implementations"](/doc/three-imp.pdf), a dissertation by Kent Dybvig, author of Chez Scheme. It uses a stack-based VM.
  - the use of a byte-code VM is key to realizing Scheme's continuations and 
    tail-recursion: this implementation (and all future implementations) will be 
    properly tail-recursive.
- the `object.hh` header contains the `OBJECT` datatype, which offers an efficient representation of latently typed objects within C++.
  - `OBJECT` instances will also offer support for manually-invoked mark-and-sweep GC.
- extensions in Scheme's environment are provided by specially bound closures.
- WIP: macros

## Language Features / Digressions from Scheme

0.  Language is dynamically typed, but with support for 'assert' (cf Typed Racket) for refinement typing upon monotype system
1.  No block comments supported
2.  Like R7RS and unlike older Scheme revisions, identifiers are case-sensitive.

Extensions
- `p/invoke` mechanism (differs from dotnet because require explicit binding in interpreter)

## Build instructions

0.  Ensure you run `git submodule update --init --recursive` to fetch all dependencies.
1.  Build with CMake: will require a C++20-compliant compiler.

## Plan

In the near future, will work on...
- compliance with R7RS-Small, then later older RnRS
- emitting WASM, either by...
  - embedding the interpreter and source in WASM using Emscripten
  - compiling VM bytecode to WASM.
  * main problem is the 'nuate' instruction is dynamically generated on call/cc <br/>
    can use first Futamura projector if possible to peval this interp against known 
    bytecode
