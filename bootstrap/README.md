# Chibi bootstrap loader

All language and compiler libraries live under `src/`. This directory is a
loader view: `lofi` points at `../src/lofi`, and `application` exposes the
explicit host helper `(application manifest bootstrap)` from `../src/application`. Use `chibi-scheme -I bootstrap`, so
Chibi resolves its own `(scheme base)` instead of the product library in
`src/scheme/base.sld`. Host scripts import `(lofi compiler bootstrap)`; product
Scheme and Lofi source both import the public `(lofi compiler)` library.

Libraries and product programs use `.sld`. Executable Chibi orchestration
scripts retain `.scm`; that suffix does not select a product language. The
benchmark freezer materializes this view as ordinary files in its private
snapshot and records their hashes.
