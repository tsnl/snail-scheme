# SFIR benchmark corpus

The corpus keeps all 57 workloads from R7RS benchmarks revision
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. Each directory contains the
canonical input, an external original Chez program, source provenance, and a
bare `main.sfir` when its complete port exists. Adapted Chez controls expose
representation changes separately. Rust implementations remain in
[`../wasm-reference`](../wasm-reference).

There are currently 51 static SFIR programs. Forty-nine were serialized once
from the resolved IR of reviewed complete ports, including Peval, Pi and
Chudnovsky. Cat and WC have complete direct SFIR character loops and file
lifecycles and matching adapted Chez controls; target validation is pending. Compiler,
CTak, Fibc, Dynamic, Scheme and SLaTeX still need complete SFIR sources. The
[manifest](corpus.json) distinguishes source presence, Wasm validation, native
validation and measurement. Source presence proves none of the latter three.

`lambda` and `let` have one body expression, `if` has both branches, and
sequencing uses lexical `begin`. No target macro or derived Scheme form runs
during preparation. The one-off conversion expanded macros with the old
frontend outside the product, then retained resolved binding identities with
unique local names. Administrative lambda applications from that expansion
remain visible. Literal constants retain their original representation.
Each `migration.json` identifies the pinned source and input, reviewed port
hash, conversion utility hash and authored SFIR hash. This is provenance, not
a claim of behavioral equivalence before target execution.

## Preparation and validation

```sh
python3 benchmarks/sfir/runner.py inventory
python3 benchmarks/sfir/runner.py prepare --output /tmp/sfir-check --benchmarks ack \
  --compile-timeout 1800
python3 benchmarks/sfir/runner.py verify --output /tmp/sfir-check
python3 benchmarks/sfir/runner.py validate --output /tmp/sfir-check
```

Preparation copies static source files, compiler/runtime/build support, Rust
sources and pinned runtime inputs into a new directory. It records content
digests and explicit positive finite build/run timeouts. The default compile
timeout remains 1200 seconds. Mutable checkout files are never referenced by
the frozen driver; immutable Nix tools are identified by invocation path and
digest. Rustup dispatchers are identified explicitly and do not yet establish a
frozen selected Rust toolchain.

Validation invokes the SFIR compiler, whose build contract always runs Binaryen,
and retains both raw and optimized Wasm. Every process has a terminal record,
including stdout, stderr, duration, failure and timeout. Timeout cleanup kills
and drains the process group. A successful compile does not establish successful
execution. The first integrated host route handles scalar/typed-container
kernels with their complete predicates. Other host routes and native lowering
remain visible as pending while they are integrated. Native must lower the
exact optimized Wasm used for Wasm validation.

There is no timing command yet. Clean timing requires a frozen comparison plan
covering SFIR, Chez and Rust, with host/target differences recorded, and must
remain separate from instrumentation and compilation. Historical Scheme
results under `benchmarks/results` are unchanged and do not count as SFIR
validation or measurement.

## Focused clarity review

A fresh independent explainer, without repository access, described the runner
as freezing inputs, establishing target evidence, and only then admitting an
explicit clean protocol. Informed critique retained immutable tool references
instead of copying whole installations, while requiring copied mutable
dependencies and explicit unsupported host routes. Tests exercise source
tampering, checkout independence, escaping/symlinked dependencies, timeout
configuration, and a process with a live child. No generic callback or plugin
framework was introduced.
