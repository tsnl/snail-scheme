# Tensor training acceptance criteria

All criteria are **planned**. The [tutorial](README.md) progresses from a reference
computation to a captured graph and a real training application. T08 is a typed
kernel extension; the optional Mandelbrot view is a graphics exercise, not a
replacement for MNIST training.

| ID | Exercise | Required evidence |
| --- | --- | --- |
| T01 | Evaluate tiny dense layers and the loss on CPU; validate dataset metadata. | Independent expected values, explicit scalar/shape contracts, 28×28 images and ten classes, verified dataset splits/hashes. Ordinary tests use small offline fixtures. |
| T02 | Capture Scheme tensor functions, inspect the graph, and compile with two configurations. | Typed IR records shapes, operations, origins, and effects; invalid shapes/control flow fail before launch. Capture performs no training or hidden data/device IO. Artifact identities include graph/signature/compiler/configuration dependencies. |
| T03 | Check autodiff for scalar, matmul, broadcast, reduction, shared-node, and loss cases. | Central finite differences away from discontinuities agree with analytic gradients. Proposed initial bound: `abs(error) <= 1e-4 + 1e-3 * abs(reference)` in the high-precision reference profile. Unsupported derivatives fail; any tolerance adjustment is justified against an independent oracle. |
| T04 | Run identical forward, backward, and update graphs on CPU and a real GPU. | Compare small f32 cases using a recorded initial tolerance of `1e-4 + 1e-3 * abs(reference)`. Report precision/backend and justify operation-specific bounds. Parameters remain device-resident; measured command sizes are independent of retained weight bytes. Fence-delayed work cannot access released buffers. |
| T05 | Train the proposed MLP on MNIST and evaluate the frozen configuration on the test split. | GPU execution, decreasing training loss, and a target of at least 95% test accuracy within ten epochs. Record seeds, hyperparameters, dataset/artifact hashes, split separation, device, and elapsed time. Establish the baseline before calling this a passing test; no current result is claimed. |
| T06 | Stream metrics to the workbook; pause, checkpoint, resume, cancel, and reload a step. | Controls run while a dispatch is pending; checkpoint restores weights plus optimizer/RNG/data position at a completed step. Compare resumed and uninterrupted runs within specified numerical limits. Cleanup respects GPU fences and connection ownership. Incompatible layouts require migration/restart. |
| T07 | Build the vendored application with CPU/GPU configurations and a native/browser split. | The build runtime loads the source artifact and invokes exported `build` once. Chibi-hosted capture and library compilers produce completed artifacts plus service requirements before success; the build actor then retires. Shipped execution runs those artifacts. Dependency tracking invalidates affected outputs; build heaps/closures/device objects do not leak across stages. |
| T08 | Add one typed kernel and derived host/device layout. | One type source determines packing, alignment, binding metadata, and target validation; an actual dispatch checks layout. A derivative rule is verified or the operation is explicitly rejected by autodiff. No requirement that a kernel declaration be directly callable in Scheme. |
| T09 | Exercise external storage above a 32-bit address range and reject an invalid resource domain. | A sparse/mock storage provider verifies offsets beyond 4 GiB without a huge download or allocation. Full-width u64 ranges round-trip without floating-point conversion or truncation, checked copies enforce bounds, and foreign-device/stale references are rejected or explicitly remapped. |

T09 extends T04's resource exercise; MNIST is too small to test the external-range
requirement by itself. The integration test must exercise that boundary deliberately.

## Test profiles

The **reference profile** runs small deterministic graphs and gradient checks,
initially using Chibi-hosted libraries. The **device profile** compares those same
graphs on an actual GPU. The **training profile** uses the real verified dataset,
a real GPU, and the browser workbook. Missing hardware/data is a reported skip or
unavailable profile, never a passing training result.

Gradient checks should use high-precision CPU arithmetic and a justified finite
difference step. GPU comparison permits documented floating-point differences;
neither all-device bitwise equality nor universal numerical accuracy is promised.
Use tests that can detect an incorrect gradient even if some training loss falls.

## Dependencies and remaining choices

Required libraries include typed tensor IR, a reference evaluator, reverse-mode
autodiff, an initial GPU lowering/compiler, binary storage, and device resource
ownership. Actor hosting, futures/streams, browser DOM support, and the build
manifest are shared with the other projects. The initial task is a tractable
operator subset, not full JAX compatibility or automatic tracing of arbitrary
Scheme side effects.

Choose the first backend, kernel subset, numerical precision policy, graph control
flow, alias/reuse rules, dataset distribution, and training configuration before
implementation. T05's accuracy/time budget is a proposed test gate to establish
experimentally, not permission to report a toy fixture as MNIST training. Capture,
autodiff, compilation, and execution must remain separately inspectable.
