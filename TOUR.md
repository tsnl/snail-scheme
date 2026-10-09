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
    lowerer -> stack VM instructions -> LLVM text
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
`compile` invokes the hosted Scheme compiler; `write_manifest` generates the
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
[`compiler.sld`](src/snail-scheme/compiler.sld). `compile-file` reads the source,
expands it, lowers the resulting HIR, and writes LLVM text. An optional VM dump
shows the representation immediately before LLVM emission.
`time-stage` measures each phase when `--timing` binds `timing-port` to stderr.
Imported-library reading belongs to expansion timing. The driver separately
reports Cargo build time, including execution when it invokes `cargo run`.

`read-source` runs the file parser and reports failures with the reader's source
position. `library-loader` applies the same operation to imports. `library-path`
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

## Functional tree composition experiment

[`react.sld`](src/snail-scheme/react.sld) is an independent Chibi-hosted prototype
for composing document, GUI, and other trees. `create-element` records a host tag
or component procedure, properties, and unrendered children. `render` resolves
selected components into a forest of ordinary `(tag props child ...)` data,
preserving strings and numbers and flattening list fragments. Property values
remain opaque. This module does not participate in the compiler pipeline.

[`examples/react.scm`](examples/react.scm) demonstrates document and GUI
descriptions. [`doc/react.md`](doc/react.md) records the implemented contract and
the remaining questions about host integrations and state. The composition tests
join the existing Chibi suite in `tests/snail-scheme/test.scm`.

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
`tuple` and `named-tuple` gather the parts of a grammar rule.

[`syntax-parser.sld`](src/snail-scheme/syntax-parser.sld) is the grammar built
from those combinators. `s-file` accepts a complete sequence of forms; `s-expr`
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
steps. `expand-program` separates initial imports from the body. Import
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

[`lower.sld`](src/snail-scheme/lower.sld) begins with `lower-program`.
`program-libraries` orders libraries after their dependencies, and
`library-items` places their initialization before the program body. Global
storage is assigned by binding identity. `local-definitions` gathers the cells
belonging to one activation and stops at nested lambdas. `free-definitions`
continues through nested lambdas: a parent may need to carry an outer binding
solely so that it can construct a child closure.

`lower` dispatches over HIR expressions. Each lowering operation receives the
label that should run afterward and returns its own entry label. This explains
why `lower-items` constructs continuations backward even though execution follows
source order. `lower-lambda` creates the procedure body and emits captures of its
free cells. `lower-application` evaluates arguments left to right, pushes each
argument, evaluates the operator, and emits a call. `lower-conditional` gives the
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

## Emitting and assembling LLVM

[`llvm.sld`](src/snail-scheme/llvm.sld) follows the output file's order.
`write-llvm-program` writes a program ABI version, Rust service declarations, inline instruction
functions, constant data, count accessors, and the program body.
`write-vm-instructions` emits the `snail_vm_*` functions as `internal alwaysinline`.
Reference, assignment, capture, push, and test handlers implement actual word
loads, stores, and tag tests. Closure construction and control transfers call
Rust services for their variable-sized work.

`write-handler-entry` establishes the automatic collection safepoint.
`write-checked-pointer` branches around failed Rust services. A handler loads a
source word before requesting storage that might move its source, then publishes
the result before another instruction can collect. LLVM uses `ptr` to copy one
target-sized tagged word; the copied word is never dereferenced as an object.
The false, unspecified, and uninitialized encodings agree with `Value` in Rust.

`write-data` serializes bytes and constant indices. `write-initialization` builds
constants and primitive globals, constructs the root closure, and enters it.
`write-instruction` emits one labeled block per VM instruction. Known successors
branch directly; calls and returns feed `write-dispatch`. Its switch contains
procedure entries and non-tail return addresses. The `u32::MAX` destination
stops execution; another unexpected destination reports an invalid instruction
address.

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
ownership together. `Value` is one `usize`. Odd words encode signed fixnums;
other tags encode characters and singleton values. Aligned heap addresses encode
boxed objects. The immediate integer range is `-2^62` through `2^62 - 1` on a
64-bit target and `-2^30` through `2^30 - 1` on a 32-bit target. `Heap::integer`
boxes values outside that range, preserving all `i64` integers on both targets.
Floating-point numbers are boxed `f64` values. `Number` is a temporary decoded
arithmetic value, not the stored Scheme representation.

The concrete types include `Pair`, `Vector`, `Cell`, `Closure`, `Record`,
`RecordType`, strings, symbols, primitives, numbers, and ports. Each implements
`SnailSchemeObject::mark`, which visits its strong Scheme references. The small
`object!` macro supplies those implementations; there is no closed object enum
standing in for dynamic dispatch. An aligned allocation header owns a
`Box<dyn SnailSchemeObject>` and its mark bit, keeping the trait object's metadata
out of the tagged word.

The heap owns headers in an address-keyed map. `find`, `get`, and `get_mut` look
up that ownership before performing a checked Rust downcast. They never turn an
untrusted integer address directly into a Rust reference. Returned references
borrow the heap. An unrooted value is invalid across collection; allocation can
reuse its old address, so this safety check does not promise permanent identity
for stale values.

`Heap::allocate` does not collect. `Heap::collect` uses an explicit worklist and
marks an object before following its children; `sweep` drops unreachable objects
and resets surviving mark bits. This handles cycles without moving objects or
recursing through the host stack. Collection scheduling uses the allocation
count since the last sweep and a budget fixed at that sweep, so each allocation
does not move the threshold farther away. Statistics count objects, not bytes.

## Activations, continuations, and Rust services

[`runtime/src/vm.rs`](runtime/src/vm.rs) holds the machine's roots and control
state. An `Activation` owns local slots, its closure, and its operand-stack base.
Each local stores either a direct value or a shared cell created on first capture.
A return frame saves an activation and resume label. A consumer frame saves the
procedure that should receive a producer's multiple values.

`close` consumes captured cells and creates a closure. `call` takes the prepared
arguments and operator, saves the caller for an ordinary call, or replaces the
activation for a tail call. `dispatch` then advances explicit call and return
actions until generated Scheme code needs to resume. `enter_closure` checks
arity, installs direct parameter and local values, builds a rest list when needed,
and returns the procedure entry label. `return_values` reuses the same dispatcher.
No Scheme call recursively enters generated code through the Rust call stack.
Primitive outcomes distinguish one value, multiple values, and control requests.
`set_result` reuses the VM's result vector for ordinary single-value publications.

`slot`, `capture_slot`, `single_slot`, `result_slot`, and `push_slot` are the
checked storage services used by LLVM instruction bodies. Capturing a direct
local allocates and publishes its shared cell without collecting. Later captures
reuse it. A capture selects the cell itself; a lexical reference selects either
the direct value or the cell's contents. Slot pointers are
short-lived: growing the underlying vector can invalidate them. These services
do not collect, and generated code must finish its loads and stores before the
next safepoint.

`safepoint` checks collection pressure or `SNAIL_GC_STRESS`. `collect` gathers
roots, runs the heap collector, removes dead weak symbol entries, and records
the elapsed monotonic time. `roots`, `Activation::roots`, and `Frame::roots`
account for globals, constants, results, pending arguments, current and saved
activations, multiple-value consumers, and current ports. Symbols kept only by
the intern table can die; a live symbol keeps its identity.

The explicit `collect-garbage` primitive requests a `Collect` action. The VM
publishes its unspecified result and collects only after the consumed inputs
are no longer needed. `gc_statistics` reports collection count, cumulative and
maximum collection nanoseconds, allocation and reclamation counts, live objects,
and peak live objects. The measured collection interval includes root gathering
and weak-table cleanup.

[`runtime/src/lib.rs`](runtime/src/lib.rs) is the C ABI boundary.
`boundary` records errors and contains unwinds where the build supports
unwinding; stopped machines make later services return their stopped values.
`handler` additionally performs the entry safepoint. The `snail_rt_*` functions
expose the VM services, while `snail_const_*` and `snail_global_primitive` build
startup data. Release builds abort on unexpected Rust panics. Scheme errors use
the VM's explicit error state.

[`runtime/src/primitives.rs`](runtime/src/primitives.rs) dispatches builtins.
`numeric_arguments` decodes numbers before checked arithmetic;
`compare_integer_float` avoids first rounding a large exact integer to `f64`.
The pair, vector, bytevector, string, character, and record operations validate
types and indices before use. `Vm::string` borrows text for reads;
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

The tests follow the same boundaries. [`tests/snail-scheme/test.scm`](tests/snail-scheme/test.scm)
runs the CLI, reader, combinator, syntax-parser, and pattern suites under Chibi.
The Rust modules contain their representation, GC, primitive, port, and
continuation tests. [`scripts/test-backend`](scripts/test-backend) compiles
bootstrap and semantic fixtures, verifies LLVM, links both targets, and executes
them under GC stress. [`scripts/test-cli`](scripts/test-cli) exercises CLI modes,
artifact publication, literal arguments, and native/WASI execution.
The backend error fixture checks arity, undefined reads,
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
checks. Captured locals use cells, values remain dynamically checked, and
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
