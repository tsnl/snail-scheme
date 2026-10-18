# Lofi

Lofi is a typed functional language and compiler target. Scheme libraries share
its compiler and runtime, so application rules, state and presentation can be
written together and compiled to WebAssembly.

Start with the [five application tutorials](lofi/tutorials/index.md) to build
a counter, an inventory and a small shared browser board. Each tutorial has
runnable source, exercises and a connection to the larger Siegework application.

For the language itself, read the [overview](lofi/index.md),
[Scheme forms and macros](lofi/macros.md), and [type system](lofi/types.md).
The [application reference](lofi/applications.md) explains state ownership,
effects, browser hosting and reload. The [native backend guide](native/index.md)
covers lowering WebAssembly to native executables.

The book is built from the repository's `main` branch. Source files and build
instructions are in the [repository](https://github.com/tsnl/snail-scheme).
