# A graph that learns handwritten digits

**Planned integration tutorial.** Ordinary Scheme functions compose a tensor graph.
A compiler library captures it, checks types and shapes, differentiates it, and
generates CPU or GPU artifacts. The application trains an MNIST classifier and
streams progress to an interactive workbook built with the chat tutorial's UI.

Aim for `build.scm`, `model.sld`, and `training.sld`; tensor/autodiff/compiler
machinery belongs in reusable libraries. Build-time graph capture has no hidden
training or device effects. Shipped execution owns GPU buffers and dispatches
compiled work. A shader declaration can be compiler input without being a callable
Scheme procedure.

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
