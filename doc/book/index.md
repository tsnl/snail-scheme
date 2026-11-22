# `snail-scheme`

**`snail-scheme` is a statically-typed Scheme successor**, for building
applications, compiling to WebAssembly with garbage collection.
Its compiler is written in the language and compiles itself.

- [The language](snail-scheme/index.md): types, mutable heap objects, capabilities, suspension,
  libraries and the compiler.
- [Tutorials](snail-scheme/tutorials/index.md): complete programs, starting with
  [`snail-scheme` in ten minutes](snail-scheme/tutorials/tour.md).
- [Siegework](games/index.md): a colony game written in `snail-scheme`.
  **[Play it](play/siegework/)** in a browser with WebGPU.
- [The path tracer](graphics/tracer.md): glTF scenes path traced in the
  page. **[Open the viewer](play/viewer/)** and drop your own `.glb` on it,
  or pick a sample.
- Splats: 3D Gaussian Splatting drawn in the page, sorted on the GPU.
  **[Open Splats](play/splats/)** and drop a trained scene's `.ply` on it.

Source lives in the [repository](https://github.com/tsnl/snail-scheme);
[getting started](https://github.com/tsnl/snail-scheme/blob/main/doc/getting-started.md)
explains the tools. The book describes implemented contracts and marks
proposals explicitly. [GitHub issues](https://github.com/tsnl/snail-scheme/issues)
track open work.
