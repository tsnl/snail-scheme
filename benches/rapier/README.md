# A Rapier vehicle driven by Snail Scheme

This example links Rapier 3D 0.36.1, in double precision, into a program compiled
by the WasmGC compiler. The Snail shell creates a fresh track, allows the car to
settle for 180 ticks, records the chassis height and wheel contacts, then applies
a force at each wheel for 120 ticks. Each tick advances the physics by 1/60 s.
It checks that all four wheels supported the chassis and returns its longitudinal
displacement. [Rapier vehicle guide](https://rapier.rs/docs/user_guides/rust/character_controller/)

Rust owns the floor, chassis and vehicle controller. Snail passes scalar controls
and keeps the observations in an ordinary record. Each program instance owns
one track. Closing or resetting it drops the Rapier world. The example's Cargo
crate links the standard scalar services and Rapier into one provider for the
existing Snail linker. The example’s build script selects this provider.
A game target would need its build to select it too. The standard compiler
and runtime build independently.

From the repository root in its Nix shell, build and run the same module on
Node and headless Chromium. The first build downloads the locked crates.

```sh
benches/rapier/build
node benches/rapier/check.mjs
```

Node, Chromium and a separate Wasmtime 48.0.7 run measured 21.33 m in two
simulated seconds at 1,750 N per wheel and less than a millimetre at zero
force, including after a reset. A WasmGC-capable WASI preview 1 host can
repeat the trial by calling `_initialize()` once and `travel(f64) -> f64`
with 0, 1750 and 0 on the same instance.
The complete optimized demonstration is about 1.68 MiB, or 696 KiB gzipped.
The check exercises the Rust boundary and the vehicle on a flat track. Last
Mile's street geometry, vehicle tuning and saved-game format are separate work.
