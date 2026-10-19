# Chibi loader view

This directory exposes `src/lofi/` and `src/application/` through symlinks.
Host scripts use `chibi-scheme -I "$repo/bootstrap" SCRIPT ...`, so Chibi
resolves its own `(scheme base)` instead of `src/scheme/base.sld`.
Absolute paths work outside the repository root.

Host scripts import `(lofi compiler bootstrap)` and `(lofi host ...)` services.
Product Scheme and Lofi sources import the public `(lofi compiler)` library.
Unit tests add `-I "$repo/tests"` for `(lofi host test-utils)`.

The benchmark freezer materializes the loader view as ordinary files in its
private snapshot and records their hashes. Libraries and product programs use
`.sld`; executable Chibi orchestration scripts retain `.scm`.
