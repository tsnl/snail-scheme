# Small application examples

Start with the [five application tutorials](../../doc/book/lofi/tutorials/index.md).
Build a counter, an inventory and a saved browser board in small runnable steps.

| Example | Purpose | Expected result |
| --- | --- | --- |
| `counter.sld` | Typed commands and direct dispatch | `42` |
| `inventory.sld` | Immutable purchase with refusal cases | `42` |
| `testing.sld` | Local transition and typed send descriptions | `42` |
| [Marker board](marker-board/README.md) | Saved browser state, quads, shaders and reload | An orange marker and a local white cursor |
| `state.sld` | Lower-level explicit word codec | `42` |

From the repository root, build a pure example and print its return value:

```sh
mkdir -p build/examples
chibi-scheme -I bootstrap tests/applications/build.scm \
  "$PWD" "$PWD/examples/applications/counter.sld" "$PWD/build/examples/counter.wasm"
node examples/applications/run.mjs build/examples/counter.wasm
```

Substitute `inventory`, `testing` or `state` in both commands to run that example.
The browser board has its own explicit build recipe. Run all tutorial checkpoints
with `scripts/test-application-tutorials`.
