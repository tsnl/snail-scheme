# Chibi host services

These libraries support the Chibi compiler and build scripts through the
`bootstrap/lofi` loader view. Their paths follow `(lofi host ...)` names.

- `wasm.sld` serializes structured Wasm into WAT.
- `wasm-optimize.sld` assembles and optimizes with Binaryen.
- `runtime-wasm.sld` builds and links the Rust Wasm scalar services.
- `build-host.sld` runs commands with inherited streams.
- `process.sld` captures commands, files and evidence.
- `json.sld` reads and writes host protocols and evidence.
- `chromium-trace.sld` records scoped compiler/build trace spans.

Managed references belong to the Wasm engine. Build and test commands can use
`tools/host/process-supervisor.rs` to enforce deadlines and reap descendants.
