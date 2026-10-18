# Make an immutable inventory

Build an inventory with fifty units of ore and buy something costing eight.
The result is forty-two units, while the original inventory still contains
fifty. An unaffordable purchase and a negative price leave the state unchanged.

Start with [the counter](counter.md) to learn `application` and `dispatch`.
The complete source is
[`inventory.sld`](https://github.com/tsnl/snail-scheme/blob/main/examples/applications/inventory.sld).

## Give the state a name

Inside the library's `begin`, define:

```scheme
(define-immutable-record Stock stock
  (ore I32 stock-ore stock-ore-set))
```

This requires `(scheme immutable)` in addition to the counter's imports.
`Stock` is the type, `stock` constructs it, and `stock-ore` reads the field.
`stock-ore-set` returns a replacement record. Its name has no `!` because it
does not mutate the old record.

For example, `(stock-ore-set (stock 50) 42)` produces a stock value containing
`42`. It takes the new field value, not an amount to add or subtract.

## Put the purchase rule beside the handler

```scheme
(application inventory (state Stock 1) (stock 50)
             (buy (state (cost I32))
                  (no-effects
                   (if (and (>= cost 0) (<= cost (stock-ore state)))
                       (stock-ore-set state (- (stock-ore state) cost))
                       state))))
```

The two comparisons give the subtraction its meaning. A cost must be
nonnegative and affordable. Otherwise the handler returns the original stock.
With nonnegative initial stock, every accepted purchase preserves nonnegative
stock. This is a rule enforced by this operation, not something implied by
the `I32` field type.

In an application with fixed prices, accept a product choice
and look up its cost on the authority. This example accepts the price directly
to make the arithmetic visible.

## Run the checkpoint

The finished `answer` initializes the inventory, dispatches `(buy 8)`, and
then tries `(buy 100)` and `(buy -1)` against the result. It returns the remaining
ore only if the retained old stock and both refusal cases have the expected
values; otherwise it returns `0`.

```sh
mkdir -p build/examples
chibi-scheme -I bootstrap tests/applications/build.scm \
  "$PWD" "$PWD/examples/applications/inventory.sld" "$PWD/build/examples/inventory.wasm"
node examples/applications/run.mjs build/examples/inventory.wasm
```

Expect `42`. Follow the values in the source:

| Value | Operation | Ore |
| --- | --- | --- |
| `before` | Initialize | 50 |
| `after` | Buy for 8 | 42 |
| `refused` | Try to buy for 100 from `after` | 42 |
| `negative` | Try to buy for -1 from `after` | 42 |
| `before`, read again | No operation on this retained value | 50 |

## Try the boundaries

In the finished source, change `(buy 100)` to `(buy 0)`. Rebuild: the
checkpoint still returns `42`, because a free purchase leaves stock unchanged.

Then try buying the exact balance. Replace `answer` temporarily with:

```scheme
(define answer
  (ann (lambda ()
         (stock-ore (transition-state (dispatch inventory (stock 50) (buy 50)))))
       (-> I32)))
```

Expect `0`. With `(buy 51)`, expect `50`. Restore the finished checkpoint
when you are done.

The old values stay usable because all updates construct replacements.
The compiler does not prove that every handler is pure: placing a mutable
vector inside a record and modifying that vector would require more care.
Keep the stored values immutable for this programming model.

Next: [build local controls](commands.md) that send commands to a separate
state owner.
