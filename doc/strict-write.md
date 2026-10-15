# Strict typed datum output

`(snail write)` writes the concrete `Datum` representation from `(snail datum)`
through `(snail io)` output ports. Scheme owns formatting and graph traversal.
Rust receives scalar Unicode characters and port IDs through the same typed
exports on Wasm and native64; no legacy value ABI or Scheme root crosses that
boundary.

| Operation | Signature |
| --- | --- |
| `write-datum` | `Datum, OutputPort -> Unit` |
| `display-datum` | `Datum, OutputPort -> Unit` |
| `write` / `display` | `Datum, OutputPort -> Unit` or `Datum -> Unit` |

The named fixed-arity functions contain the implementation. Static overloads
choose them directly, supplying `current-output-port` for the one-argument form.
They add no newline. Current output is the stable borrowed stdout described by
[the I/O contract](strict-io.md); output to a file remains explicit.

```scheme
(import (snail strict) (snail io) (snail datum) (snail write))
(write (datum-list (datum-symbol (string->symbol "answer"))
                   (datum-number (exact-number 42))))
(newline)
```

`write` emits `()`, `#t`/`#f`, character literals, quoted strings, unambiguous
symbols, existing canonical decimal Number text, proper/dotted lists, `#(...)`
vectors and `#u8(...)` bytevectors. Number formatting goes through
`number->string`, retaining arbitrary Integer/Rational values, complex shape,
inexact zero signs and nonfinite spelling. It never narrows a Number to I64.
As with the existing Number formatter/parser, manually constructed numeric
representations can normalize on reading: for example an exact complex zero
imaginary part can become a real representation.

Strings escape their delimiter, backslash, LF, CR, TAB and remaining C0/C1
control scalars. Hex string escapes end with `;`. Character literals use named
space/newline/tab/return, hexadecimal control scalars, or the scalar itself.
All other Unicode scalars, including non-BMP values, retain their exact spelling.
Symbols print bare only when the reader's affirmative identifier grammar accepts
their name and numeric parsing returns no number or numeric error. Other names,
including empty and numeric-looking names, use `|...|` with scalar escapes.

`display` follows the same container traversal while emitting strings,
characters and symbol names directly. Numbers and container syntax keep their
written spelling. For example a displayed list containing a newline character
includes that actual newline between its list delimiters. Displayed text need
not be readable as a datum.

## Finite graph semantics and lifetime

Output never changes the supplied data. One query-local inspection records
mutable storage identities and visits each unique object's children once.
An active entry distinguishes a cycle from ordinary sharing. Pair aliases
sharing both Refs and vector aliases sharing their backing array identify the
same node, even if their private Datum view IDs differ. Strings and bytevectors
also participate by backing storage identity. All retained values and pending
continuations remain ordinary traced Scheme data, live only for this call.

An acyclic shared value expands at every occurrence. When any cycle is present,
all repeatedly encountered mutable objects receive graph labels in first-output
order: `#0=(a . #0#)` or `#0=#(a #0#)`, for example. Assigning a label before
printing its children closes cycle edges. A labelled list tail uses dotted
syntax to preserve the tail's identity. Both writer entry points terminate on
finite pair/vector graphs; cyclic display uses the same graph-label extension.
No implicit warning is emitted.

The policy for `write` follows Chez's switch from ordinary sharing expansion to
graph notation on cycles, documented under
[`print-graph`](https://cisco.github.io/ChezScheme/csug10.3.0/io.html).
Strict character/symbol/bytevector spelling follows the strict reader's R7RS
syntax, independently of Chez's additional lexical forms. Chez's nonterminating
cyclic `display` behavior is not reproduced. The current strict reader rejects
`#n=` and `#n#`; graph output is implemented here, graph input is not.

The identity table uses direct linear lookup with `datum-eq?`, preserving the
existing storage contract without a new backend identity representation. Worst
case lookup work is mutable-node encounters times table entries. Rendering
acyclic sharing may itself produce much more output than the number of unique
nodes. Explicit continuations make inspection and rendering stack safe through
deep car chains and vector nesting; only hexadecimal scalar formatting uses
bounded recursion (at most six digits). No user callback or concurrent mutation
may intervene during inspection/rendering. Output is incremental, so an I/O
error can leave a written prefix. Fatal errors and traps retain the existing
terminal invocation cleanup contract.

`scripts/test-strict-write` retains command records and runs exact output,
reader round trips, Unicode/escaping, numeric domains, shared storage and cyclic
graphs, deep nesting, stdout identity/ownership and terminal I/O failures through
raw linked Wasm, optimized linked Wasm and native64. It observes actual WASI
descriptor closes and native resource releases.
