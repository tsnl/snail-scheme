# Crazy ideas

Future research bets to explore through snail-scheme. The ambition is to build a
research platform where we can change what a program is, how we interact with it,
and what evidence we require before trusting it.

These are hypotheses and possible experiments. Some have working research
prototypes elsewhere; making them useful across ordinary software could take
decades, or turn out to be the wrong direction. The platform should let us try
different answers, compare them, and discard them without starting over.

## Long bets

### Programs as persistent, structured objects

A program could live as a graph of definitions, dependencies, types, examples,
and evidence. Text would be one way to view and edit that graph. A definition's
identity could be independent of its displayed name, with documentation and
proofs attached to the exact version they describe.

[Unison](https://www.unison-lang.org/docs/the-big-idea/) explores this through
content-addressed definitions and names stored separately from their identities.
The longer bet is an ecosystem in which versioning, collaboration, dependency
management, and code review understand program structure directly.

An experiment could store a small language's resolved definitions by content,
keeping source locations and display names as separate metadata. Renaming a
bound variable should preserve identity; changing a referenced definition should
change the dependent identity. Hashing syntax does not establish equivalence
between different algorithms.

Later, a review could expose changes to effects, contracts, and dependencies
alongside source edits. The hard questions concern recursive definitions,
migrations, trust in cached evidence, and preserving the portability and
inspectability we get from text files. Structural merging still cannot infer
every contributor's intent.

### Stable specifications and replaceable implementations

A library's durable artifact could be its semantics, permitted effects, and
resource constraints. Implementations would be replaceable ways of satisfying
that contract, specialized for different hardware or workloads.

[Rosette](https://emina.github.io/rosette/) combines programming with solvers for
verification and synthesis. A longer bet is that maintaining software becomes
largely a matter of refining contracts and examples, while tools search for,
check, and measure candidate implementations.

An experiment could synthesize expressions in a tiny, finite language from a
specification. A separate checker could exhaustively establish equivalence over
a bounded input domain. From there, explore checked rewrites, solver-backed
contracts, and generated proofs. Keep the scope of each guarantee explicit:
passing examples, bounded checking, and a general proof establish different
things.

AI could propose programs and proofs while a small checker validates the
evidence. The difficult part remains the specification: it may omit necessary
behavior, encode the wrong requirement, or be as costly to maintain as the
implementation. This bet pays off when specifications are more stable and easier
to trust than the implementations they permit.

### Programming by editing consequences

A programmer could edit an output and ask the environment to propose changes to
the program that produced it. Moving a shape might introduce a parameter;
aligning several shapes might introduce a shared constraint or an abstraction
for repeated elements.

[Sketch-n-Sketch](https://ravichugh.github.io/sketch-n-sketch/) demonstrates this
combination of code editing and direct manipulation for HTML and SVG. The longer
bet extends it to reports, transformations, protocol traces, and reusable
abstractions learned from demonstrations.

An experiment could evaluate arithmetic expressions while retaining provenance
from output values to source expressions. Editing a result would produce a
small set of candidate source changes, which the user could inspect and choose.
A later experiment could infer a shared parameter from several related edits.

The central problem is ambiguity. Moving one object could mean changing its
coordinate, moving its parent, or changing a layout rule. Multiple programs can
produce the same observed output. The environment needs ways to express intent,
constrain updates, and show consequences beyond the edited example.

### Distributed systems as whole programs

A language could describe interactions across machines, persistent state, and
trust boundaries as one program. Its semantics would account for where values
live, which participant may act on them, and what remains valid as messages are
delayed or machines fail.

[Choral](https://arxiv.org/abs/2005.09520) explores choreographic programming:
describe an interaction globally and generate implementations for its roles.
[CALM](https://bloom-lang.net/calm/) connects logical monotonicity with the
possibility of consistent distributed computation without coordination, under
its model's assumptions.

An experiment could describe a protocol between two roles and derive their
local actions. Run both in a deterministic simulator that explores message
ordering, delays, and explicit failure cases. Check a narrow property, such as
agreement about which messages are permitted next.

The longer bet brings communication, deployment, persistence, upgrades, and
authority into a coherent language model. Partial failure and latency remain
real. The challenge is expressing their consequences precisely while retaining
control over performance and allowing independently owned systems to evolve.

### Programs as models that infer and learn

A program could describe how observations arise, then support simulation and
inference from that same model. A model of a machine could generate sensor
readings or infer likely faults from actual readings.

[Gen](https://www.gen.dev/tutorials/intro-to-modeling/tutorial) explores
executable probabilistic models and programmable inference. The longer bet is
making uncertain and learned behavior a composable part of software semantics.
A component could expose its beliefs, supporting observations, assumptions,
and the information that would help distinguish competing explanations.

An experiment could add finite probabilistic choices and observations to a
small evaluator, then enumerate possible executions exactly. This supplies a
reference against which to compare approximate inference. Later, investigate
incremental updates as observations arrive and explicit computation budgets.

A particularly interesting extension is adaptive behavior inside mechanically
checked constraints: strategies may change, while certain actions remain
forbidden. Statistical confidence and logical guarantees need separate
representations. Inference can be expensive, assumptions can be wrong, and the
world can change outside the model.

## Directions that could support these bets

### Effects, handlers, and capabilities

Explore interfaces that describe behavior as well as input and output values:
filesystem access, mutation, failure, suspension, or nondeterminism. Handlers
could supply different interpretations of operations, allowing the same
computation to run against real resources, a simulator, or a test environment.

[Koka](https://www.microsoft.com/en-us/research/project/koka/) is a useful
reference for effect types and handlers. An initial experiment could handle
state or finite nondeterministic choice in a small evaluator. Later, ask which
effects can be inferred and how to present them clearly in higher-order code.

Capabilities address a related question: which particular resources a
computation is authorized to use. An effect describing file access and a
capability granting access to one directory convey different information.
Experiments should preserve that distinction.

### Ownership, isolation, and resource-aware execution

Explore how types can describe mutation, sharing, lifetime, and safe concurrency
without making every program difficult to write. Possibilities include affine
values, isolated mutable regions, noncopyable resources, and inferred lifetime
information. Swift's work on noncopyable and nonescaping types offers one
[reference point](https://forums.swift.org/t/swift-language-focus-areas-heading-into-2025/76611).

A small experiment could compare shared immutable values with uniquely owned
values that permit in-place updates. Continuations and closures are useful
stress cases: capturing control or an environment must preserve resource rules.
Measure the annotation burden and diagnostic quality alongside runtime costs.

### Selective verification and independently checked evidence

Explore stronger guarantees around small, valuable boundaries: a parser's input
accesses, an encoder/decoder relationship, or a transformation's preservation of
meaning. Compare ordinary types, refinements, solver queries, and explicit
proofs for expressing those properties.

A [2026 compiler-verification experience report](https://arxiv.org/abs/2602.20082)
describes an AI assistant constructing a Rocq proof with human guidance and a
related proof as a template. It suggests a useful separation between proposing
evidence and checking it. The platform should make the trusted assumptions and
the statement actually established visible.

### Live programming with meaningful incomplete programs

Explore a language where a missing expression has an expected type and a known
context, and complete parts of the program remain available for inspection or
evaluation. Errors and unfinished work could be represented explicitly.

[Hazel](https://hazel.org/) investigates this through typed holes. A small
experiment could evaluate expressions containing holes to partial results,
report what each hole requires, and preserve that information across edits.
Later, combine evaluation, examples, debugging, and proof obligations in one
interactive environment.

### Specialization and explicit execution choices

Explore how to express algorithms clearly while retaining control over data
layout, allocation, locality, vectorization, and movement between processors.
Domain-specific representations could retain information that would be hard to
recover from low-level operations.

[MLIR](https://mlir.llvm.org/) supplies a reference for composing representations
and transformations at different abstraction levels. A small experiment could
specialize a pure computation for known inputs or representations and compare
the result with a reference evaluator. Later, investigate different execution
targets and ways to explain why an optimization did or did not apply.

## Qualities to preserve in a research platform

These experiments suggest useful freedoms to retain as snail-scheme develops:

- **Inspectable representations.** Make syntax, binding, elaboration, checked
  terms, and execution inspectable. Preserve source correspondence without
  assuming that source positions or displayed names are semantic identities.
- **Explicit semantic boundaries.** Distinguish evaluation, type normalization,
  code transformation, and effects. Experimental extensions should state which
  guarantees they preserve and which new assumptions they introduce.
- **Multiple interpreters and analyses.** Make it practical to compare ordinary
  execution with tracing, symbolic execution, partial evaluation, or simulation.
  These may need different representations; a single universal evaluator should
  remain a hypothesis to test.
- **Controlled interaction with the world.** Provide places to intercept and
  record effects for deterministic experiments. Replay needs explicit treatment
  of external state, randomness, scheduling, and irreversible actions.
- **Independent checking.** Keep experimental transformations and generated code
  accountable to reference semantics, differential tests, bounded checks, or
  proofs appropriate to the claim being made.
- **Versioned experiments.** Make it possible to retain and compare definitions,
  execution traces, assumptions, and results across changes. Persistent state
  and code evolution are research questions of their own.
- **Small demonstrations.** Prefer a tiny example that makes an idea's benefit
  and failure modes visible. Record expressiveness, usability, compilation cost,
  and runtime cost; any of them may make an otherwise elegant idea impractical.

The interesting combinations cross these boundaries: effect handlers supporting
distributed simulation, ownership constraining continuations, typed holes
guiding synthesis, and provenance supporting edits to results. We should be
able to investigate those combinations without assuming in advance that they
all belong in one final language.
