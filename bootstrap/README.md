# Chibi loader view

This directory exposes `src/lofi/`, `src/native/` and `src/native.sld` through
symlinks. Host scripts use `chibi-scheme -I "$repo/bootstrap" SCRIPT ...`, so
Chibi resolves its own `(scheme base)` instead of the product library in
`src/scheme/base.sld`. Absolute paths work outside the repository root.

Host build scripts import `(lofi compiler bootstrap)` and, when producing native
artifacts, `(native)` separately. Product Scheme and Lofi sources import the
public `(lofi compiler)` library. Library dependencies share this include root
and the installed Chibi/SRFI libraries; native package tests additionally use
`-I "$repo/src/native/tests"`.

The benchmark freezer materializes this loader view as ordinary files in its
private snapshot and records their hashes. Libraries and product programs use
`.sld`; executable Chibi orchestration scripts retain `.scm`.
