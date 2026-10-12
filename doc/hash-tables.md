# Hash tables

`(scheme hash-table)` supplies the R7RS-large / [SRFI 125](https://srfi.schemers.org/srfi-125/srfi-125.html) interface. Chibi uses
its installed library while hosting the compiler; compiled programs use
collector-owned Scheme buckets and entries.

```scheme
(import (scheme base) (scheme hash-table))
(define memo (make-hash-table eq?))
(define key (vector 'mutable))
(hash-table-set! memo key #f)
(vector-set! key 0 'changed)
(hash-table-contains? memo key)             ; #t
(hash-table-ref/default memo key 'absent)   ; #f
```

Identity, `eqv?`, `equal?`, string, and case-insensitive string equality select
matching default hashes. Custom equality needs an explicit hash procedure or a
hashable comparator. Hash procedures must return nonnegative exact integers;
equal keys must receive equal hashes. Mutating a key is supported when equality
and hashing depend only on identity. Content-based keys must keep their hash and
equality behavior stable while stored.

The table owns ordinary strong Scheme references. WasmGC owns collection on
Wasm; BDWGC owns it on native. Wasm identity hashing uses weak JavaScript keys
and scalar IDs; native hashing mixes the nonmoving tagged reference. Neither
keeps an otherwise unreachable key or self-referential table alive. Rust
structural hashing uses owned ABI roots and bounded unfolding, so cyclic keys
terminate and bisimilar cyclic values receive compatible hashes.

Insertion grows the bucket array at a bounded load. Entries cache their hash,
so growth invokes no user callbacks. Deletion changes only private bucket
spines. Lookup is expected constant time with well-distributed hashes; collisions
still require equality comparisons. Iteration order and numeric hash codes are
unspecified and may differ across processes and backends.

A structural version detects insertion, deletion, or clearing inside hash,
equality, and traversal callbacks. Updater and intern failure callbacks may
change the table: their subsequent write performs a fresh lookup. As an
extension, replacing an existing value during traversal is supported; traversal
observes the live entries. Replacing an equivalent key updates its stored
representative too. Immutable tables reject mutating operations.

Constructor implementation hints are accepted but currently do not enable weak
or synchronized tables. `(scheme comparator)` implements only the constructors
and accessors needed here, including eq/eqv/equal comparators; it does not claim
full SRFI 128 support. Case-insensitive hashing matches the runtime's existing
per-character lowercase comparison, which is not full Unicode case folding.
Legacy optional hash arguments are accepted and ignored as specified by SRFI 125.

`make test` checks the Scheme table operations under Chibi.
`scripts/test-backend --target both` executes compiled tables, forced collisions,
cyclic structural keys, callback mutation, immutable tables, and numeric keys.
The suite checks ABI root balance, stresses native collection, and checks that
Wasm identity hashing does not retain discarded objects.
