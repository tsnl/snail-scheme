# Command line

The command is a Wasm artifact run by the [Node.js host](nodejs.md). Chibi
bootstraps it; the compiled command can then execute ordinary Scheme build
scripts and rebuild the same Wasm artifact.

```sh
chibi-scheme -h512M -I src build.scm
node --no-warnings scripts/run-wasi.mjs build/snail-scheme.wasm --help
node --no-warnings scripts/run-wasi.mjs build/snail-scheme.wasm examples/fibonacci.scm
```

`-I DIRECTORY` and `-IDIRECTORY` add library search paths. `--` ends interpreter
options. Arguments after `SCRIPT` pass through literally, with the script's path
as the first `command-line` element. Help runs before the Binaryen preflight.
An ordinary script executes its top-level forms once; defining `main` does not
select it automatically. A build may explicitly select a zero-argument `main`
whose result must be an exit status from 0 to 255.

The command platform selects filesystem, ports, environment, clock, diagnostic,
and build handlers. WASI supplies the default IO; JavaScript supplies subprocess
and publication operations. All Scheme-callable extension operations use the
[local ABI](../abi.md). See [effect interfaces](../effects.md) for replacement
providers and [backend instructions](../../backend.md) for tools and checks.

A project's build script can make a complete artifact:

```scheme
(import (scheme base) (snail-scheme build) (snail-scheme chromium-trace))
(with-chromium-trace-to "build.json"
  (lambda () (build-wasm "." "app.scm" "dist/app.wasm")))
```

The script chooses every path. A failed build keeps the previous published
artifact and reports retained intermediates. Successful builds publish one
module or one module-plus-dependencies generation atomically.

This command runtime has no node `spawn`, `connect`, connection clients, or
message dispatch loop. Running a subprocess is a blocking build operation;
it does not implement the node startup and supervision contract.
