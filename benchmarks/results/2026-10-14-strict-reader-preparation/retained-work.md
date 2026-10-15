# Retained work

The static audit is reproducible with `inspect-retained-work.py`. Each excerpt
records its complete source path/hash and its own hash in `retained-work.json`.
The binary modules, generated LLVM and compiler command records remain in the
archive. This audit checks surviving code paths; it does not measure dynamic
allocations or trace every internal field in every outer repetition.

In both production linked Wasm modules and both native-final Scheme modules,
`export0` calls `function210`. That function compares the caller's original
count against its running index, calls the foreign pathname barrier once,
opens the file, invokes the complete worker, closes the file, and tail-calls
itself with the next index and result. The final branch evaluates the original
numeric-tolerance or structural-datum predicate. There is one static open,
close, barrier and repetition-call site in this loop. Full-count WASI traces
separately establish their dynamic counts and complete read-through-EOF cycles.

Sum1's `function201` calls `function198` to read the next typed datum. EOF returns
the current accumulator. The other path unwraps the real number and tail-calls
the same worker with `f64.add(next-value, accumulator)`. `function198` retains
the immediate syntax-error boundary, and `function137` retains character input,
lookahead, token classification and scalar numeric parsing. The final predicate
still subtracts the parsed expected value and applies the original `1e-9`
tolerance.

Read1's `function203` retains the `do` loop state. EOF returns its previous-datum
parameter. Otherwise it reads the next datum, unwraps the old current datum,
increments the original unused index and tail-calls itself with those updated
bindings. `function129` retains the complete structural result comparison.
The original upstream source, exact adapted source and edit reversal remain
the authority for simultaneous-binding and error-order semantics.

Native LLVM preserves the same paths. Sum1's `wasm.bench` enters `f.62`, then
outer loop `f.61`; the worker is `f.60`. Read1 enters `f.66`, then `f.65`, with
its read/loop paths in `f.63` and `f.64`. The outer functions each retain one
call to their barrier wrapper, one open wrapper `f.2`, one close wrapper `f.3`
and one recursive repetition call. These wrappers call the same Rust scalar
exports by their concrete ABI names. Generated GC rooting and checked object
accesses remain visible in the LLVM excerpts.

Rust inlines the two workload functions into their respective `main` functions.
Both optimized Wasm mains retain file-open/read calls and loops. Sum1 retains
the sequential f64 addition followed by the input-loop branch; its second
static f64 addition converts elapsed time. Read1 retains `Reader::new`,
`Reader::skip_space` and `Reader::datum` calls within the buffered-reader path.
Both native LLVM mains retain their opaque `black_box` boundaries. The output
predicate remains after the original count loop and before Rust's elapsed-time
reporting. The full raw/optimized/native canonical controls and stream probes
validate the observed results of these paths.

The Rust reader's owned textual atoms, buffers and vectors differ from Scheme's
typed recursive datums and interned symbols. Optimizers may inline wrappers or
remove allocations with no observable effect. Retained loop/call sites and
complete canonical outputs establish this source-program comparison; they do
not establish identical allocation or general failing-input behavior.
