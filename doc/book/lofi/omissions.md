# Notable omissions

Lofi is deliberately smaller than its first plan. These parts were dropped
because they would cost more than they give the programs Lofi runs today;
each can return if a program needs it.

{{#include ../../redesign.md:omissions}}

Some smaller features are planned but not yet implemented: complex numbers
and mutable pairs in the dynamic Scheme libraries, mutually recursive local
functions, superclasses, literals at a generic numeric type, and
overflow-checked arithmetic. The [language issue](https://github.com/tsnl/snail-scheme/issues/456)
tracks these gaps.
