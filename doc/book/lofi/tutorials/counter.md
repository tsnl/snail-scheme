# Make a counter with typed commands

Build a program that adds two to forty and returns `42`. This isolates the
application's smallest operation: compute a replacement from an old state and
a command. No state service, network or browser is involved.

Use the [shared setup](index.md#set-up-once). The complete source is
[`counter.sld`](https://github.com/tsnl/snail-scheme/blob/main/examples/applications/counter.sld).

## Declare state and commands

Read or enter the following in `examples/applications/counter.sld`:

```scheme
(define-library (examples counter)
  (export answer)
  (import
   (scheme base)
   (application reducer)
   (only (lofi core) ann -> I32))
  (begin
    (application counter (state I32 1) 0
                 (add (state (amount I32)) (no-effects (+ state amount)))
                 (reset (state) (no-effects 0)))
    (define answer
      (ann (lambda () (transition-state (dispatch counter 40 (add 2)))) (-> I32)))))
```

`define-library` gives the code an identity. `export` makes `answer` available
to the build. Each import adds the names used by the program; `(scheme base)`
is the supported compiled Scheme subset, rather than Chibi's whole library.

Read the `application` declaration as “`counter` stores an `I32`, with schema
version `1`, initially `0`.” The version describes the state's meaning for host
snapshots. It is not the current counter value.

The macro creates `add` and `reset` as typed command constructors. `(add 2)`
describes work. `(dispatch counter 40 (add 2))` performs the handler calculation
using `40` as the supplied state. It returns a transition, so
`transition-state` extracts `42`. `no-effects` constructs a transition without
requests to the outside world; it can still contain a changed state.

`ann` writes a type explicitly. `(-> I32)` means a zero-argument procedure
returning an `I32`, which is the scalar entry the runner invokes.

## Build and run

```sh
mkdir -p build/examples
chibi-scheme -I bootstrap tests/applications/build.scm \
  "$PWD" "$PWD/examples/applications/counter.sld" "$PWD/build/examples/counter.wasm"
node examples/applications/run.mjs build/examples/counter.wasm
```

Expected output:

```text
42
```

The build helper selects the exported `answer` procedure and writes Wasm.
The runner invokes that procedure and prints its return value. The result is
computed by the compiled Scheme code.

## Use the initializer

Replace only the `answer` definition with:

```scheme
(define answer
  (ann (lambda ()
         (let* ((before ((application-initial counter)))
                (after (transition-state (dispatch counter before (add 2)))))
           after))
       (-> I32)))
```

Rebuild and run the same commands. The result is now `2`, because `before` is
the declared initial value `0`. The doubled parentheses first get the
initializer procedure and then call it. This creates a value; it does not
look up a live runtime owner's state.

Try replacing `(add 2)` with `(reset)` and expect `0`. Then restore the original
`answer` so the supplied checkpoint again returns `42`. Keep arithmetic small
here; the example does not implement an overflow policy for a production counter.

## Find this in Siegework

In [`game.sld`](https://github.com/tsnl/snail-scheme/blob/main/apps/siegework/src/siegework/game.sld), `match-app`
uses the same declaration. Its `advance` handler calculates a replacement
`World`, and `new-run` returns a fresh initial world. The larger state does
not change the dispatch model.

Next: [make an inventory](inventory.md), where an operation can leave state
unchanged because a purchase is unaffordable.
