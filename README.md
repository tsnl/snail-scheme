# `snail-scheme`

`snail-scheme` is my personal minimal Scheme implementation.

It offers a nice-to-use C++ API that is easily extended using C++'s native OOP
principles.

It includes a basic interpreter (SSI) written in C++.
- the interpreter is based on Ch3 of ["Three Implementations"](/doc/three-imp.pdf), using a heap-based VM.
  - the use of a byte-code VM is key to realizing Scheme's continuations and 
    tail-recursion: this implementation (and all future implementations) will be 
    properly tail-recursive.
  - implementation of Ch4 is partially complete, moving most data-structures to the stack.
- the `object.hh` header contains the `OBJECT` datatype, which offers an efficient representation of
  latently typed objects within C++.
  - `OBJECT` instances will also offer support for manually-invoked mark-and-sweep GC.
- 

## Language Features / Digressions from Scheme

0.  Language is dynamically typed, but with support for 'assert' (cf Typed Racket) for refinement typing upon monotype 
    system
0.  No block comments supported
0.  Like R7RS and unlike older Scheme revisions, identifiers are case-sensitive.
