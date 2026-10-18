# Send a command from local controls

Build a local control that counts its uses and asks a shared inventory to
deposit ore. You will return a request from one handler, then deliver it to
another.

The complete source is
[`testing.sld`](https://github.com/tsnl/snail-scheme/blob/main/examples/applications/testing.sld).
It uses the immutable `Stock` record from [the inventory tutorial](inventory.md).

## Define the receiving application

```scheme
(application inventory (state Stock 1) (stock 10)
             (deposit (state (amount I32))
                      (no-effects (stock-ore-set state (+ (stock-ore state) amount)))))
(define inventory-target (destination match-owner inventory))
```

`destination` attaches this typed application to an owner understood by the host.
The browser host names the shared owner `match` and exposes it as `match-owner`.

For this lesson deposits are small positive constants. A real deposit service
would also establish an amount bound and handle addition overflow.

## Return a request from the control

```scheme
(application controls (state I32 1) 0
             (confirm (state (amount I32))
                      (transition (+ state 1)
                                  (list (enqueue inventory-target (deposit amount))))))
```

The local state counts confirmations. A transition contains the next count and
an immutable list of effects. `enqueue` constructs a send effect whose typed
destination must accept the command. Command ownership is checked independently
of state type; using `I32` in two apps would not make their commands interchangeable.

Read `(dispatch controls 0 (confirm 7))` as:

```text
old local count 0 + confirm 7
    -> new local count 1
    -> one send description requesting deposit 7
```

At this point, the shared inventory has not changed. The transition contains
everything the host needs to deliver the request later, after committing the
local change. A pure dispatch does not run the host's delivery loop.

## Inspect the request and run

The finished checkpoint extracts the first returned effect and checks
`effect-send?` before using `effect-owner` and `effect-a`. It separately
dispatches a deposit to verify the receiver. It also checks that a notice is
a different effect variant.

```sh
mkdir -p build/examples
chibi-scheme -I bootstrap tests/applications/build.scm \
  "$PWD" "$PWD/examples/applications/testing.sld" "$PWD/build/examples/testing.wasm"
node examples/applications/run.mjs build/examples/testing.wasm
```

Expect `42`, the checkpoint's success value. The inventory starts at `10` and
the direct test deposit makes it `15`; `42` is not the inventory balance.
This checkpoint tests returned values and effect descriptions, not networking.

## Act as the host for one request

To make the distinction concrete, temporarily replace `answer` with:

```scheme
(define answer
  (ann (lambda ()
         (let* ((before ((application-initial inventory)))
                (sent (dispatch controls 0 (confirm 7)))
                (effect (car (transition-effects sent))))
           (if (effect-send? effect)
               (stock-ore
                (transition-state
                 (dispatch inventory before (deposit (effect-a effect)))))
               0)))
       (-> I32)))
```

Rebuild and expect `17`. Here you explicitly dispatch the second operation,
using the inspected payload. The code knows there is exactly one kind of send
in this example. A general host resolves the effect's destination and handler
identity; do not build a router by treating every effect as a deposit.

Change `(confirm 7)` to `(confirm 9)` and expect `19`. Restore the finished
checkpoint after the exercise.

Next: [build a saved marker board](board.md). The browser host delivers the
requests so you can see local and saved state respond to input.
