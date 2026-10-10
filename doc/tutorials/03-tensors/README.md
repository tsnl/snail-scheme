# A graph that learns handwritten digits

Build a tensor program in Scheme, differentiate it, compile it for a GPU, and
train a small MNIST classifier. Watch loss and accuracy in an interactive workbook,
pause at a checkpoint, and resume. This project makes the compiler a library
inside an application rather than a separate language the user must switch to.

**Status: project specification, not a runnable tutorial yet.** The
[platform design](../../why-snail-scheme.md) supplies the actor model; the
[requirements](requirements.md) define numerical and integration acceptance.
Scheme spelling in this document is illustrative, not a shipped tensor API.

## The Resin precedent

Resin's older Python
[graph module](https://github.com/tsnl/resin/blob/f40cd66a482acf08f4bafeb55fba9dc805548498/src/resin/graph.py)
on `archive/main-v8a` represents shapes, scalar types, views, tensor operations,
and reverse-mode gradient construction. Its
[MNIST sketch](https://github.com/tsnl/resin/blob/f40cd66a482acf08f4bafeb55fba9dc805548498/examples/demo_mnist.py)
builds a loss graph but leaves parameter initialization, updates, and the training
loop as TODOs. It is inspiration for graph construction, not evidence of a
completed training run; its placeholder image size is not the MNIST specification.

The later Rust
[training example](https://github.com/tsnl/resin/blob/70ebadc4367527c85105d48c40a96df0ba6fbbe8/examples/train_mnist.rs)
on `archive/main-v14` goes further: one captured step includes forward evaluation,
gradients, and SGD, with CPU/wgpu backend selection and device-resident parameters.
The Python `main-v3` work remains relevant for
[host/shader layout](https://github.com/tsnl/resin/blob/aa1e3612843297e94cc98102f44f6524b4528b6c/src/resin/draw_3d.py#L2815),
but graph capture is the starting point for this tutorial, rather than translating
GLSL surface syntax.

## 1. Run a tiny tensor computation on the CPU

Start with a scalar squared-error example and a small dense layer. The tensor
library has explicit operations, shapes, and scalar types; ordinary Scheme
functions compose them. A reference evaluator supplies concrete CPU results.

```scheme
;; Proposed tensor library operations; arithmetic on tensors is explicit.
(define (linear weights bias input)
  (tensor+ (matmul input weights) bias))

(define (predict parameters images)
  (linear (output-weights parameters) (output-bias parameters)
          (relu (linear (hidden-weights parameters)
                        (hidden-bias parameters)
                        images))))

(define (loss parameters images labels)
  (mean (cross-entropy-with-logits
          (predict parameters images) labels)))
```

MNIST uses 28×28 grayscale images and ten digit classes, with 60,000 training and
10,000 test examples. Flatten images to 784 inputs for the first network.
Use the [dataset specification](https://www.tensorflow.org/datasets/catalog/mnist)
and verified dataset files, not the dimensions in an old prototype.

**Checkpoint T01:** inspect shapes and compare the small forward computation with
hand-computed/reference results. Keep dataset download out of ordinary unit tests.

## 2. Evaluate the builder to capture a graph

Call the same composition functions with symbolic tensor values. Each operation
adds a typed node to a graph rather than running a GPU kernel. Scheme remains a
dynamic language for constructing that graph; the graph's scalar types, ranks,
shapes, and effects must be checked before compilation.

```scheme
;; Proposed graph construction during build evaluation.
(define training-graph
  (capture
    (lambda (parameters images labels)
      (let* ((error (loss parameters images labels))
             (gradients (grad error parameters))
             (next (sgd parameters gradients 0.01)))
        (values error next)))
    training-signature))

(define training-artifact
  (compile-tensor-graph training-graph gpu-configuration))
```

`training-signature` gives the parameter tree and batch tensor types. `grad`
transforms the scalar loss graph with respect to parameters; `sgd` builds update
nodes. Compilation creates an artifact plus binding/layout metadata. No images
have been classified and no parameters updated by merely capturing this graph.

This follows the useful distinction in
[JAX's tracing model](https://docs.jax.dev/en/latest/tracing.html): host evaluation
constructs a representation for later execution. A Scheme `if` can branch on
known build data, but a condition on a symbolic tensor needs a graph control-flow
operation. Do not accidentally treat a symbolic Scheme record as true and select
a branch. Randomness, effects, and unsupported operations need explicit contracts.
Ordinary record-based tracing cannot intercept Scheme's truth test: that diagnostic
needs checked capture syntax or a restricted builder, not arithmetic overloading
alone. Begin with explicit graph operations while that syntax is designed.

**Checkpoint T02:** inspect a typed graph and its artifact. Reject incompatible
shapes and unsupported dynamic control flow at their source locations. Include
the signature, compiler version, and target configuration in the artifact identity.

## 3. Differentiate before trusting training

Reverse-mode autodiff should handle shared subexpressions, broadcasting, matmul,
reductions, and the chosen loss. Accumulate contributions when a value is used
twice. Reject an unsupported derivative rather than silently treating it as zero.
Specify the derivative convention at nondifferentiable points such as ReLU at zero.

**Checkpoint T03:** compare gradients with central finite differences on small,
well-conditioned inputs away from those points. Include a shared-node example
such as `x*x + x*x`; a missing gradient accumulation must fail before MNIST is run.
Use an independent reference for both loss and derivatives.

## 4. Give the graph to a GPU actor

The actor owns the device, compiled programs, buffers, and submitted work. A
training coordinator sends a program reference, parameter references, and a batch
reference. It receives completion and small metrics. Parameters stay on the device
between steps; a new Scheme actor can coordinate each bounded step if useful.

```scheme
;; Proposed coordinator fragment. Resource records have derived S-expression codecs.
(define (run-batch gpu program parameters batch)
  (invoke gpu 'dispatch
          (make-training-dispatch program parameters batch)))
```

Scheme's parameter tree is a tree of typed resource references at this boundary,
not a tree containing millions of Scheme numbers. A pure graph step returns the
next parameter values; the backend may reuse storage only when its ownership and
dependency analysis permits. Device fences govern reclamation, not the return
from the Scheme call alone.

Large datasets and checkpoints use storage references with checked 64-bit ranges
and binary transfers. Message serialization still applies to commands and resource
descriptions, even for an in-process GPU provider. No raw pointer into an actor's
32-bit Scheme heap is smuggled across the boundary.

**Checkpoint T04:** run the same captured graph through CPU and GPU backends and
compare outputs/updates within stated tolerances. Inspect uploads and allocations
to prove that parameters are retained rather than retransmitted every step.

An optional graphics checkpoint captures a bounded Mandelbrot iteration graph and
renders into a retained texture for display. It exercises masks/loop construction
and graph-to-renderer composition. It is neither a prerequisite for autodiff nor
a suggestion that the fractal escape computation is a useful differentiable loss.

## 5. Train and observe a real model

Use a 784→128→10 MLP with ReLU, stable cross-entropy, and SGD as the proposed first
baseline. Fix initialization and shuffle seeds, batch size, learning rate, and a
training budget in a checked-in configuration. Use training-only validation for
tuning; reserve the test split for reporting the frozen configuration.

The training coordinator connects to a dataset actor, GPU actor, checkpoint store,
and workbook. It emits a metric stream: step, loss, elapsed time, and evaluation
accuracy. The browser workbook uses the same reducer/tree/DOM approach as the
[chat tutorial](../02-chat/README.md). Pause, resume, and cancellation arrive as
ordinary handler invocations while a GPU result is pending.

**Checkpoint T05:** perform real GPU training and evaluate the held-out test set.
Loss reduction alone is insufficient: report accuracy, seeds, configuration,
dataset hashes, runtime, and device. The initial target is at least 95% test
accuracy within ten epochs; this is a proposed acceptance target, not a measured
result or a guarantee for arbitrary hyperparameters.

**Checkpoint T06:** pause at a completed step, save parameters and optimizer/RNG/
data-position state, and resume. Cancel with work in flight and release resources
after device completion. Replace a compatible compiled step only at a step
boundary; incompatible parameter layouts require explicit conversion or a restart.
Keep metric delivery and controls responsive without locking the coordinator.

## 6. Make the compiler and workbook reusable

Export the graph builder, model configuration, and application recipe as library
values. A consumer can select a CPU reference or GPU backend, native coordinator,
and browser workbook. Build evaluation produces several artifacts and service
requirements; the later runtime connects them. A compiler can be called locally
or exposed by a service without changing the graph's meaning.

**Checkpoint T07:** vendor the package and build it from a different directory.
Change model structure and rebuild only affected outputs. Capture must be testable
on the Chibi host without a GPU or browser; shipped training must execute those
outputs on the requested backend. No build-time closure or device handle becomes
an embedded constant by accident.

**Extension T08:** add one typed kernel operation through a Scheme shader dialect
and give it a derivative rule or an explicit nondifferentiable contract. Derive
host/device layout and packing from one type definition, and compile to a chosen
GPU target such as WGSL or SPIR-V. A shader declaration need not be a Scheme-callable
procedure. Validate layout and numerical behavior rather than adopting GLSL's
syntax as the application's main programming model.

## Proposed project contents

| File | Future responsibility |
| --- | --- |
| `application.sld` | Export graph/application recipes, targets, and service requirements. |
| `model.sld` | Pure network and loss composition over tensor operations. |
| `training.sld` | Coordinator handlers, step boundaries, metrics, and checkpoint control. |
| `workbook.sld` | Reducer and document/tree view of training progress. |
| `types.sld` | Shapes, parameter trees, resource records, and protocol types. |
| `fixtures/` | Tiny independent numerical cases and frozen training configuration. |
| `tests/` | Gradient checks, CPU/GPU comparisons, and the full dataset/device run. |

Tensor capture, differentiation, compilation, and device/storage providers belong
to reusable libraries. Keep their algorithms inspectable separately from this
network and application. Share the document authoring extension from chat rather
than creating another markup language for the workbook.
