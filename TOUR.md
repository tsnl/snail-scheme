# A tour of Snail-Scheme

Start with the path taken by one program, then follow the representations it
passes between modules. The compiler is Scheme. The runtime, target integration,
and executable entry point are Rust. Chibi still runs the compiler during the
normal build; compiling the compiler's Scheme sources does not change that
choice.

```text
Scheme source and imported libraries
    snail-scheme Rust driver -> hosted Scheme compiler
    reader -> syntax parser -> expander -> HIR
    lowerer -> stack VM instructions -> immutable LLVM objects -> LLVM text
    Cargo build script -> LLVM optimization -> target object
    Rust runner -> generated program <-> Rust runtime
```

The generated program is a specialized stack machine. Its instruction sequence
is fixed at compile time: ordinary successors become direct branches, and
procedure calls and returns select labels through an explicit dispatcher. Each
instruction's LLVM implementation is emitted by Scheme and inlined before
assembly. Rust owns values, allocation, collection, primitive operations, and
continuation frames.

## Entering the compiler

[`snail-scheme`](snail-scheme) launches the Rust command in
[`driver/src/main.rs`](driver/src/main.rs). `parse` handles compiler options
until `--`, after which arguments belong to the program. An input selects run
mode, `-o` selects build mode, and `--emit-llvm` stops after emission. `execute`
resolves source and output paths and creates an invocation-owned `Project`.
`source_file_to_llvm` invokes the hosted Scheme compiler; `write_manifest` generates the
Cargo application using the existing runner and runtime paths.

`cargo_command` selects `cargo run` or `cargo build`, and `configure_target`
sets the profile, WASI target and runner, and literal program arguments. Every
job has its own Cargo target directory, so concurrent invocations cannot replace
one another's executable. `publish` copies a finished artifact to a staging file
and renames it into place. `Project::drop` removes temporary files unless
`--keep-build` was selected. Subprocess arguments use `Command`, never a shell
command assembled from input paths.

[`snail-compile`](snail-compile) locates the checkout and runs
[`compile.scm`](src/snail-scheme/compile.scm) with Chibi. That small Scheme entry
point passes `command-line` to `compiler-main` in
[`compiler.sld`](src/snail-scheme/compiler.sld). `source-file->llvm-file` reads the source,
expands it, lowers the resulting HIR, and writes LLVM text. An optional VM dump
shows the representation immediately before LLVM emission.
Timing is centralized in [`trace.sld`](src/snail-scheme/trace.sld) and the
[`snail-trace` crate](trace/src/lib.rs). `define-traced` wraps coarse Scheme
operations; Rust scope guards cover the driver, LLVM tools, execution, and GC.
Every process writes Chromium events to `build/traces/` by default. Imported
source loading appears as nested spans inside expansion, so inclusive and
exclusive time can be inspected without subtracting counters in compiler code.
See [tracing](doc/tracing.md) for APIs and continuation limitations.

`source-file->syntax-list` composes `file->reader` from `reader.sld` with
`reader->syntax-list` from `syntax-parser.sld`, which reports parse failures with
the reader's source position. `library-loader` applies the same operation to imports. `library-path`
maps `(scheme ...)` names into `bootstrap/scheme/`; project libraries resolve
under `src/`. The loader returns located library syntax, leaving binding and
import semantics to the expander.

The historical parser inspection entry,
[`main.scm`](src/snail-scheme/main.scm), uses
[`cli.sld`](src/snail-scheme/cli.sld) to collect an input path and optional output
path, then prints parsed syntax. It defines `main` without invoking it; Chibi's
`-r` runs that procedure. Compiling the file alone therefore produces a program
that defines the procedure and exits silently. The compilation pipeline instead
enters through `compile.scm`, whose top-level form invokes `compiler-main`.

## Reading source

[`source.sld`](src/snail-scheme/source.sld) defines `loc`: filename, one-based
line, and one-based column. Locations travel with syntax and later with HIR and
VM instructions.

[`reader.sld`](src/snail-scheme/reader.sld) represents an immutable character
cursor. `file->reader` and `string->reader` establish the initial position;
`peek-reader` observes it, `next-reader` advances it, and `reader-loc` extracts a
location. Advancing returns another reader, so parser alternatives can retain
the original input without undoing mutations. Line tracking handles LF, CRLF,
and standalone CR.

[`parser.sld`](src/snail-scheme/parser.sld) builds parsers from functions of a
reader. A `parse-result` contains success or failure, a value, and the remaining
reader. `>>=` and `chain` sequence successful parses; `pmap` changes their values.
`choice` tries alternatives from the original position. `lookahead` and
`not-followed-by` inspect without consuming. `repeat` accumulates results and
rejects a parser that succeeds without advancing, preventing an infinite loop.
`tuple` and `named-tuple` gather the parts of a grammar rule. `named-tuple` runs
fields directly, retaining named values and skipping allocation of ignored
field pairs. Its construction captures procedures; names are observed after
each successful field, preserving the descriptor API. Both parsers return a
child's first failure unchanged and keep their accumulators local to each call.

[`syntax-parser.sld`](src/snail-scheme/syntax-parser.sld) is the grammar built
from those combinators. Named rules are parser values, constructed once in
dependency order; recursive references stay inside parsing callbacks. Use
`(s-file reader)` to run a parser and `(choice s-number s-symbol)` to compose
them. `s-file` accepts a complete sequence of forms; `s-expr`
chooses lists, vectors, quote abbreviations, and atoms. The remaining sections
handle delimiters, escapes, Unicode characters, identifier and numeric
spellings, and whitespace and comments. Numeric spelling recognition is wider
than the compiled runtime's current numeric subset; a successfully parsed datum
can still be rejected during lowering.

[`syntax.sld`](src/snail-scheme/syntax.sld) defines the three syntax containers:
`atom-syntax`, `list-syntax`, and `vector-syntax`. A list stores its proper prefix
and optional improper tail separately. Every node has a location. `syntax->datum`
removes that metadata when an operation needs an ordinary Scheme datum.

[`common.sld`](src/snail-scheme/common.sld) contains the lexical character
classes used by the grammar, small list and string helpers, assertions, and file
reading. Its predicates describe characters; the grammar decides how those
characters combine into tokens.

## Expanding names, libraries, and macros

[`hir.sld`](src/snail-scheme/hir.sld) defines the resolved high-level records.
A `value-definition` is a binding identity. A `name` refers to that identity,
and a `value-binding` attaches an initializer to it. Thus a renamed import, a
reference inside a closure, and the original definition can share one identity
even though their printed names differ. The expression records are literals,
applications, lambdas, blocks, conditionals, assignments, and names. Program and
library records preserve resolved imports, exports, bodies, and dependencies.
The records do not contain expansion environments.

[`expand.sld`](src/snail-scheme/expand.sld) constructs those records in three
steps. `syntax-list->hir-program` separates initial imports from the body. Import
expansion loads and caches libraries, applies `only`, `except`, `prefix`, and
`rename`, and preserves the original definition identities. Library construction
resolves exports against the completed library environment.

Body expansion first reserves directly declared identities, then discovers
body forms and installs transformers, then constructs expressions. Follow
`expand-body-chunks`, `reserve-direct-definitions`, `prepare-body-chunks`, and
`build-body-chunks` for this ordering. It lets recursive references point to
already reserved identities while macro visibility still follows source order.
`expand-expression` repeatedly expands the head and then handles a core form or
ordinary application. `expand-lambda` reserves parameter identities and expands
its body in the extended environment.

Transformer installation parses both patterns and templates.
`parse-transformer` builds rules; `parse-rule-template` records the roles of
introduced identifiers, captures, and repetitions. At a use site,
`apply-transformer` selects a rule and `instantiate-template` builds the result.
Introduced identifiers receive fresh keys, substituted syntax keeps its keys,
and free identifiers retain their definition-site fallback. These are the
pieces to follow when investigating hygiene rather than reasoning from symbol
spelling alone.

[`pattern.sld`](src/snail-scheme/pattern.sld) supplies the underlying datum
matcher. `pattern-dispatch` parses its patterns once, then tries them against
each input. `match-pattern` produces structured match records. Sequence matching
handles the fixed prefix, fixed suffix, repeated middle, and optional improper
tail; `flatten-match` creates capture alists only after a complete match succeeds.
Repeated matches retain nesting, including empty repetitions. A callback can
reject an otherwise matching branch by returning `#f`.

The expander's syntax-matching adapter connects these two modules.
`build-syntax-dispatcher` and `project-syntax` give the datum matcher a structural
view while preserving the original syntax for captures. Literal constraints use
resolved identifier identity. The datum matcher itself remains independent of
source locations and lexical environments. There is no general compile-time
Scheme evaluator here: transformer support is the dedicated `syntax-rules`
path.

## The Scheme library used by compiled programs

[`bootstrap.sld`](src/snail-scheme/bootstrap.sld) is the inventory of Rust
primitive names. The compiler supplies these through a synthetic
`(snail-scheme core)` library using `make-core-library`. It then loads the
bootstrap libraries as ordinary Scheme libraries. Chibi uses its own libraries
while hosting the compiler.

[`bootstrap/scheme/base.sld`](bootstrap/scheme/base.sld) implements derived
forms with `syntax-rules`, including binding forms, conditionals, quasiquotation,
multiple-value bindings, records, and parameterization. Its procedure sections
implement lists, association searches, multi-list `map` and `for-each`, container
conversion, and cycle-aware equality. The native boundary supplies individual
object operations; higher-level traversal remains Scheme code that future
compiler optimizations can improve.

The remaining bootstrap modules are deliberately thin. `cxr.sld` defines the
longer `car`/`cdr` compositions. `file.sld` wraps file opening with
`call-with-port`. `char.sld`, `process-context.sld`, `time.sld`, and `write.sld`
expose their corresponding primitive groups. `parameterize` and port wrappers
preserve multiple values on normal returns; nonlocal exits and `dynamic-wind`
are outside this bootstrap subset.

[`runtime.sld`](src/snail-scheme/runtime.sld) exposes the explicitly nonstandard
`string-contains`, `collect-garbage`, and `gc-statistics` operations. This keeps
benchmark-specific runtime measurements separate from the standard libraries.

## Lowering HIR into a machine

[`lower.sld`](src/snail-scheme/lower.sld) begins with `hir-program->vm-program`.
`program-libraries` orders libraries after their dependencies, and
`library-items` places their initialization before the program body. Global
storage is assigned by binding identity. `local-definitions` gathers the bindings
belonging to one activation and stops at nested lambdas. `free-definitions`
continues through nested lambdas: a parent may need to carry an outer binding
solely so that it can construct a child closure.

`lower` dispatches over HIR expressions. Each lowering operation receives the
label that should run afterward and returns its own entry label. This explains
why `lower-items` constructs continuations backward even though execution follows
source order. `lower-lambda` creates the procedure body and emits captures of its
free values or cells. `boxed-definitions` combines explicit assignments with
forward captures needed for recursive initialization. `lower-application` first
recognizes binary calls to never-written core numeric bindings by identity.
Those become `add`, `subtract`, or comparison instructions with a known successor,
without a call frame. Shadowed, initialized, or assigned bindings and other
arities retain ordinary calls. `lower-procedure-call` emits a frame for a
non-tail call, evaluates arguments left to right, pushes each, evaluates the
operator, and applies it. Tail calls shift arguments instead. `lower-conditional` gives the
test two explicit destinations. Tail position is passed through these operations
rather than recovered later from emitted code.

`literal-constant!` records literals in a pool. Pair and vector entries refer to
child entries created earlier, so startup can construct them in pool order.
`emit!` assigns labels and retains each instruction's source location.

[`vm.sld`](src/snail-scheme/vm.sld) defines this compilation representation:
a program carries its entry, root local count, instructions, constants, globals,
and primitive bindings. An instruction carries an operation, operands, label,
known successor where applicable, and location. `write-vm-program` is the readable
dump. These instructions are distinct from LLVM bitcode and are not interpreted
by a bytecode-fetch loop.

The binary numeric instructions and their measured effect are described in
[the numeric instruction notes](doc/numeric-instructions.md).

## Emitting and assembling LLVM

[`llvm.sld`](src/snail-scheme/llvm.sld) follows the output file's order.
`write-vm-program-as-llvm` writes a program ABI version, Rust service declarations, inline instruction
functions, constant data, count accessors, and the program body.
`write-vm-instructions` emits the `snail_vm_*` functions as `internal alwaysinline`.
Reference, assignment, argument, frame, shift, and test handlers implement
actual stack loads, stores, and branches. Numeric handlers consume two stack
operands: fixnum arithmetic and comparisons stay in LLVM; boxed values and
fixnum overflow call Rust's `snail_rt_numeric` before continuing. Fallback keeps
the enclosing frame and all live roots published. Application and return are shared
blocks in the generated function. Rust services prepare heap-backed operations
and native calls; they do not own ordinary call/return transitions.

Handlers check single-value contexts and service errors before using results.
They load source words before a service can relocate stack storage and publish
live words before allocation boundaries. LLVM uses `i32` for tagged words and
`ptr` for storage addresses; ordinary handlers dereference stack/slot addresses. The false,
unspecified, and uninitialized encodings agree with Rust's `Value`.

`write-data` serializes bytes and constant indices. `initialization-body` builds
constants and primitive globals, constructs the root closure, and enters it.
`program-blocks` reserves immutable block references; `instruction-body` defines
one block per VM instruction. Known successors branch directly; calls and returns
feed `dispatch-body`. Its switch contains
procedure entries, non-tail return addresses, and reserved apply/return/consumer
actions. The `u32::MAX` destination
stops execution; another unexpected destination reports an invalid instruction
address.

`vm-functions` gives VM operations their typed LLVM function references.
`dispatch-targets` preserves first-occurrence order with a private bitmap for
the lowerer's dense labels; sparse hand-built labels retain list membership
checks. This deduplicates switch destinations; a phi gathers instruction and shared-control
destinations at the dispatcher.

[`llvmlite.sld`](src/snail-scheme/llvmlite.sld) supplies the immutable LLVM
vocabulary used by that lowering. References precede definitions: create a
function, its blocks and SSA values, then give each block instructions and a
terminator. Instructions hold typed operands and direct block references. Loop
backedges require no mutable builder. `block-body` checks scope, phi placement,
and returns; LLVM verifies definitions and dominance. Only this module spells
LLVM syntax. Its writer streams to a port, and `indexed-name` keeps generated
numeric names as prefix/index data. See [the API notes](doc/llvmlite.md) for a
complete loop example and the supported subset.

[`runner/build.rs`](runner/build.rs) connects this module to Cargo. It reads
`SNAIL_LLVM_IR`, obtains the selected Rust target's LLVM triple and data layout
from a tiny Rust probe, and adds that metadata to the module. `optimize` runs
`always-inline`, LLVM's O2 pipeline, and verification; it also checks that no
`snail_vm_*` functions remain. `assemble` invokes `llc` and supplies the object
to Rust's final link. The runtime is linked as Rust code; this build does not
require cross-language Rust bitcode linking.

For WASI, `verify_reducible` checks that each optimized cycle has a single entry
before omitting LLVM 22's costly irreducibility repair pass. Ordinary instruction
edges form a DAG; calls and returns use the one dispatcher. This avoids quadratic
reachability storage when compiling the compiler itself. The negative VM fixture
in the CLI suite verifies that a two-entry cycle is rejected.

[`runner/src/main.rs`](runner/src/main.rs) first checks the generated program's
ABI version against `PROGRAM_ABI`, then allocates a `Vm` using the generated
global and constant counts, passes its opaque address to `snail_program`, and
reports errors and the requested exit status. `report_statistics` prints elapsed
time, GC counts and durations, object counts, and maximum saved frames when
`SNAIL_RUNTIME_STATS` is set. The Cargo workspace contains the driver, runner,
and runtime; the driver and runtime are default members, so ordinary Rust checks
do not need a generated Scheme program.

## Values, objects, and collection

[`runtime/src/object.rs`](runtime/src/object.rs) keeps representation and
ownership together. `Value` is a 32-bit `usize`; other pointer widths are
rejected. Its tags preserve v3: odd fixnums, immediate symbol IDs, zero null,
halfword characters/singletons, and aligned nonzero heap pointers. Fixnums range
from `-2^30` through `2^30 - 1`; boxed integers preserve the remaining `i64`
range. All floats are boxed `f64`: v3's immediate float32 encoding cannot fit a
32-bit word. `Number` is a decoded arithmetic value, not a heap object.

One `Boxed<T>` allocation contains an aligned kind/mark header and concrete
payload. Pairs, cells, text, and vectors keep v3's field model, adapted for Rust
ownership; additional kinds cover closures, records, ports, and primitive IDs.
`find`, `get`, and `get_mut` check the tag and kind before direct field access.
There is no hash lookup, `Any`, or virtual dispatch for builtin objects.

The ownership vector is used for sweeping. `gc_mark` statically follows each
kind's Scheme fields using a worklist; `destroy_object` releases its own Rust
storage without recursively freeing children. Cycles therefore work naturally.
Only `Extension` delegates tracing and destruction through a C ABI vtable.
Its callbacks must report live same-VM edges and cannot allocate managed
objects, collect, reenter Scheme, or unwind. All internal pointer access requires
live same-heap words; a copied value is not a durable host root.

Allocation never collects. Collection scheduling uses allocations since the
last sweep and a budget fixed at that sweep. Statistics count objects, not bytes.

## Stack storage, continuations, and Rust services

[`runtime/src/vm.rs`](runtime/src/vm.rs) owns a single initialized value buffer.
Its active suffix is the downward-growing Scheme stack; saved frame positions
are depths from its high end. `State` is the fixed C-compatible register layout
shared with generated LLVM. Globals and constants have stable storage; `reserve`
moves the active suffix to a larger buffer and refreshes `stack_end`.

`prepare_apply` checks whether the operator is a closure, primitive, or saved
continuation. Fixed-arity closure entry creates no Rust or managed allocation.
`prepare_rest` constructs a list for variadic calls. Primitive invocation polls
when necessary, reverses the consumed argument region into source order, and
borrows a slice. The callable cannot collect or resize the Scheme stack.

`capture` copies the active suffix through the call's return header into an
immutable continuation object. `restore` preserves invocation values, copies
the snapshot back, and lets LLVM execute its ordinary return transition. The
snapshot can be invoked repeatedly. Assigned binding cells retain identity
across snapshots; immutable captures are copied directly into closures.

`Runtime` owns heap, ports, argv, and symbol names. Rust callables receive these
services without VM control. `Allocation` adds managed construction for a
GC-free burst; only the VM creates that capability at an allocation boundary.
Neither a managed allocation nor capability destruction triggers collection.
`roots` gathers globals, constants, registers, active stack words, multiple
results, and current ports. Saved snapshots trace their words as heap children.
All stack metadata is tagged immediate data, so the collector never mistakes a
raw frame index for an object pointer.

One result lives in `State.a`; multiple values use a reusable vector.
`receive` transfers those results to the consumer's arguments. `apply`, multiple
values, and continuation invocation rejoin shared LLVM control blocks without
nesting native Rust calls. Explicit `collect-garbage` requests collection only
after the native operation returns. `gc_statistics` includes root gathering,
tracing, and sweeping in its collection timings.

The experimental [`runtime/src/instructions.rs`](runtime/src/instructions.rs)
implements the seven binary numeric VM handlers in Rust with the same raw-pointer
ABI, fixnum checks, result publication, and rooted fallback as the LLVM versions.
Chibi's `snail-rust-numeric` feature opts into Rust declarations; the compiler
retains LLVM definitions by default for a matched comparison.
[`benchmarks/rust-instructions`](benchmarks/rust-instructions) compares ordinary
linking with shared LTO; [the experiment report](doc/rust-instruction-experiment.md)
records its results and limits.

[`runtime/src/lib.rs`](runtime/src/lib.rs) provides ABI 3. `boundary` records
errors and contains unwinds where supported; stopped machines return stopped
values. Release builds abort on unexpected Rust panics. Startup services build
constants and primitive globals; execution services expose state, storage,
heap-backed bindings, application preparation, and snapshots.

[`runtime/src/primitives.rs`](runtime/src/primitives.rs) dispatches builtins.
A closed `Builtin` inventory records names and allocation effects; dispatch
uses enum IDs instead of copied strings. A borrowed `Arguments` view indexes and
iterates the downward stack in source order without reversing its storage.
Allocation classification happens once per invocation; builtin names are read
only when a diagnostic needs one. Numeric operations decode arguments
while traversing them, without allocating a temporary number vector;
`compare_integer_float` avoids first rounding a large exact integer to `f64`.
The pair, vector, bytevector, string, character, and record operations validate
types and indices before use. `Runtime::string` borrows text for reads;
`string_byte_offset` translates Unicode-scalar indices for substring and search.
Constructors own their output before allocating it in the heap. Record descriptors
are generative identities, and `constructor_fields` establishes field order by
name. `apply` and
`call-with-values` return dispatch requests instead of calling Scheme from Rust.
`format_value` uses its own work stack for deep structures and detects cycles
on the current print path, so shared acyclic values print normally.

[`runtime/src/host.rs`](runtime/src/host.rs) implements ports, command-line
arguments, exit, and the monotonic clock. `open_port`, `read_char`, `read_string`,
`write_port`, and `close_port` handle the port variants. String indices and read
counts refer to Unicode scalar values. File input currently loads and decodes
the complete text when opened; chunked Scheme reads consume that retained input.
`current-jiffy` uses nanosecond units from `Instant`, which does not imply
nanosecond hardware resolution. The initial host uses Rust `std` on native and
WASIp1 targets.

## Checks and benchmark measurements

The tests follow the same boundaries. Each tested Scheme module ends with a
`Tests` section containing private cases and one exported `test-<module>` entry
point. `make test` enables Chibi's `snail-tests` feature;
[`tests/snail-scheme/test.scm`](tests/snail-scheme/test.scm) calls the CLI, reader,
combinator, syntax-parser, pattern, expander, LLVM emitter, and llvmlite entries.
Shared assertions in `tests/` depend only on Scheme base and write, avoiding
cycles with the implementation modules. Importing a module does not run tests,
and normal builds omit their imports, exports, and definitions.

The expander selects library-level `cond-expand` declarations before resolving
imports or expanding bodies. It advertises `snail-scheme` independently of the
host; compiled programs therefore omit the host-only `snail-tests` branches.
Inactive branches are still read as syntax. This preserves the compiler's ability
to compile its own source files without requiring host-only testing facilities.

The Rust modules also end with their representation, GC, primitive, port, and
continuation tests under `#[cfg(test)]`. [`scripts/test-backend`](scripts/test-backend) compiles
bootstrap and semantic fixtures, verifies LLVM, links both targets, and executes
them under GC stress. [`scripts/test-cli`](scripts/test-cli) exercises CLI modes,
artifact publication, literal arguments, and native/WASI execution.
The direct LLVM fixture in [`tests/emit-llvmlite.scm`](tests/emit-llvmlite.scm)
builds a module through the public IR API. The backend error fixture checks arity, undefined reads,
single-value contexts, and integer overflow.

[`scripts/run-wasi.mjs`](scripts/run-wasi.mjs) supplies Node's WASIp1 imports,
forwards arguments and environment, and preopens the working directory. Native
and WASI run the same generated program and Rust heap model. Browser hosting,
WASIp2 packaging, and a general native embedding interface are separate work.

[`benchmarks/run`](benchmarks/run) verifies the frozen corpus, compiles each
benchmark, saves its release executable, checks its three output lines, and
optionally writes JSON samples. Each Scheme program validates an answer and
measures a fixed amount of work; changing repetitions changes the recorded work
count rather than silently calibrating it to a time limit.

`chez_runtime` selects the native Chez reference. `measure_pair` alternates
execution order while holding work and repetition counts equal;
`comparison_summary` divides Snail's median elapsed time by Chez's. Raw samples,
artifact hashes, and pairing order remain in JSON. `record_artifact` records
input hashes around successful builds; `verify_artifact` checks saved files
before `--no-build` reuses them. WASI Snail also compares with native Chez.

[`benchmarks/ablate`](benchmarks/ablate) saves runtime variants with `snapshot`,
including native/WASI executables, reusable LLVM, source hashes, and source
patches. `compare` checks that the compiler and toolchain stayed fixed, runs
equal workloads in alternating pairs, and saves raw samples with median
speedups. These comparisons isolate individual runtime changes before the
next optimization milestone.

[`benchmarks/lto`](benchmarks/lto) instead holds runtime sources fixed and
compares ordinary release, Rust-only LTO, and shared Scheme/Rust LTO. It saves
linked bitcode, builds every variant before timing, then rotates native/WASI
benchmark executions with the Chez reference. The default build is unchanged.

[`scripts/check-static-codegen`](scripts/check-static-codegen) isolates a smaller
question: whether equivalent checked fixnum helpers written in Rust and through
`llvmlite` inline into LLVM callers. It executes both on native/WASI and retains
the linked IR and assembly. This diagnostic does not change runtime primitives.

[`benchmarks/chibi`](benchmarks/chibi) compares saved Snail executables with
Chibi and Chez, rotating execution order and checking equal fixed work. Its
[`Scheme adapter`](benchmarks/chibi.scm) keeps the workload bodies unchanged and
converts Chibi substring-search cursors to character indices. The report records
Chibi's millisecond wall clock and the native pointer-width difference explicitly.

[`benchmarks/chez.scm`](benchmarks/chez.scm) keeps the canonical workload sources
shared. `copy-program` replaces their imports with the required compatibility
definitions; `compile-benchmark` calls Chez's native `compile-program` at safe
optimization level 2 before any timing begins. The adapters translate records,
clocks, bulk input, substring search, and collector statistics. Their IO
algorithms and GC accounting differ from Rust's and are documented beside the
comparison methodology. `--snail-only` deliberately omits the Chez reference.

The four benchmark modules each expose their measured operation directly:

- [`cpu.scm`](benchmarks/cpu.scm): `fibonacci` makes deliberately redundant calls;
  `fibonacci-linear` supplies an independent oracle, and `workload` combines
  checked results.
- [`memory.scm`](benchmarks/memory.scm): `sieve` mutates composite flags,
  `prime-list` retains the discovered primes, and `summarize` traverses their
  counts, sums, and gaps. Trial division checks small instances independently.
- [`io.scm`](benchmarks/io.scm): `read-matches` keeps the suffix needed for matches
  across chunk boundaries; `search-file` opens and closes one file at a time.
  Rust bulk reads and substring search make this a comparison where less work
  is available for Scheme optimization. Repeated runs use the normal page cache.
- [`gc.scm`](benchmarks/gc.scm): `make-tree` creates parent-linked cyclic trees,
  `fill-ring!` replaces older roots, and `verify-tree` checks the retained graph.
  It reports collection counts and collection time alongside elapsed time.

[`benchmarks/generate-corpus.py`](benchmarks/generate-corpus.py) explains the
original fictional text and independently computes its search answer. The
checked-in corpus and SHA-256 manifest fix its bytes; the benchmark runner does
not regenerate it. See [the benchmark notes](benchmarks/README.md) for workload
sizes, expected answers, and measurement commands.

[`Makefile`](Makefile) runs the hosted Scheme tests and formatting checks.
[`shell.nix`](shell.nix) supplies Chibi, Chez, and development utilities; Rust, LLVM,
and a WASI runner are additional tools. The formatter scripts share Scheme
indentation rules between writing and checking files. `Cargo.lock` records the
Rust workspace resolution, and generated LLVM, objects, executables, and timing
reports belong under ignored build directories.

## Reading toward the next milestone

A useful order for an optimization change is HIR identity, lowering's storage
and tail-position decisions, VM operations, then the corresponding LLVM body
and Rust service. HIR and VM dumps expose the boundaries before machine code;
benchmarks and semantic fixtures provide separate performance and correctness
checks. Assigned locals use cells, values remain dynamically checked, and
library bodies are retained. Those choices make the costs visible before type
inference changes representation or removes checks.

[The backend notes](doc/backend.md) describe build commands and current limits.
[The HIR notes](doc/hir.md) explain binding and macro contracts. The highlighted
[Dybvig thesis](doc/three-imp.pdf) provides the stack-machine starting point;
[the R7RS report](doc/r7rs-small.pdf) is the language reference. [TODO.md](TODO.md)
tracks the next work. The repository's pinned `simplify` skill describes the
independent explanation and review process used when changing these modules.
[The Rust interop design](doc/rust-interop.md) separates today's executable
linking from the scoped native calls and reusable embedding API planned next.
