# A graph that learns handwritten digits

**Planned integration tutorial.** During building, ordinary Scheme compiler calls
capture a tensor graph, check types and shapes, differentiate it, and generate
CPU or GPU artifacts. During execution, a training actor loads those artifacts,
owns GPU buffers, and exchanges progress messages with a browser workbook.

Aim for `build.scm`, `model.sld`, and `training.sld`, using reusable tensor and
compiler libraries. Start with a tiny model whose values and derivatives can be
checked independently; then add real device execution and MNIST training.
Compilation alone performs no training. A shader declaration can be compiler
input without being a callable Scheme procedure. The workbook uses the chat
tutorial's UI libraries.

## Observable checkpoints

- **T01 — Reference computation:** tiny offline fixtures check dense layers,
  shapes, loss, and dataset metadata against independent expected values.
- **T02 — Capture:** typed IR records operations, shapes, source origins, and
  effects. Invalid programs fail before launch; graph/compiler/configuration
  dependencies determine artifact identity.
- **T03 — Autodiff:** finite differences independently check scalar, matmul,
  broadcast, reduction, shared-node, and loss derivatives. Unsupported derivatives
  are errors. Begin with a high-precision reference tolerance of
  `1e-4 + 1e-3 * abs(reference)` and justify changes against an independent oracle.
- **T04 — Device execution:** CPU and real GPU forward/backward/update results
  agree within recorded precision bounds. Parameters stay on the device; command
  sizes do not grow with retained weight bytes. Cleanup waits for GPU completion.
- **T05 — Training:** a proposed baseline is at least 95% MNIST test accuracy
  within ten epochs. Establish it experimentally with a real GPU; record seeds,
  configuration, dataset hashes, split separation, loss, accuracy, and timing.
- **T06 — Interactivity:** controls work while dispatch is pending. Pause,
  checkpoint, resume, cancel, and replace a validated step without losing ownership
  of in-flight resources. Checkpoints include optimizer/RNG/data position.
- **T07 — Build composition:** one vendorable application produces graph artifacts,
  native coordinator, browser workbook, and service requirements. Local compiler
  calls are libraries; no actor boundary is necessary for compilation itself.
- **T08 — Typed kernels:** an extension shares host/device type and layout metadata,
  checks actual dispatch, and supplies a verified derivative or rejects autodiff.
- **T09 — External storage:** sparse fixtures round-trip explicit u64 ranges beyond
  4 GiB without a huge heap. Checked copies reject overflow, stale resources, and
  wrong resource domains. MNIST's size alone cannot test this requirement.

Separate reference, device, and full training profiles. Choose the first GPU
backend, operator subset, graph control flow, and precision policy from a measured
baseline. Mandelbrot can be an additional graph-capture exercise; it does not
replace autodiff and training coverage.
