# `snail-scheme`

`snail-scheme` is my personal minimal Scheme implementation.

It includes a trivial interpreter (SSI) and a whole-program optimizing compiling (SSC).

## Key Features/Digressions from Scheme

0.  Language is dynamically typed, but with support for 'assert' (cf Typed Racket) for refinement typing upon monotype 
    system
1.  Int and Float are separate data-types-- precision selection for floating point defaults to double
2.  No block comments supported
3.  Like R7RS and unlike older Scheme revisions, identifiers are case-sensitive.

## TODO

- finish parser
  - add string literals, unicode characters, support for unicode IDs.