# `snail-scheme`

`snail-scheme` is my personal minimal Scheme implementation.

It includes a basic interpreter (SSI) and a whole-program optimizing compiler (SSC).
- the interpreter is based on Ch3 of ["Three Implementations"](/doc/three-imp.pdf), using a heap-based VM.
  the use of a byte-code VM is key to realizing Scheme's continuations and tail-recursion.
- the compiler, SSC, is [will be?] written in Scheme using SSI.

## Language Features / Digressions from Scheme

0.  Language is dynamically typed, but with support for 'assert' (cf Typed Racket) for refinement typing upon monotype 
    system
1.  Int and Float are separate data-types-- precision selection for floating point defaults to double
2.  No block comments supported
3.  Like R7RS and unlike older Scheme revisions, identifiers are case-sensitive.
