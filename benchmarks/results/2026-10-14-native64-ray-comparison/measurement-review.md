# Measurement review

This is the parent’s summary of one independent explanation and one informed
critique using the repository’s simplify skill. The explainer was a fresh
Sol 6.1 agent at max effort with no inherited conversation history, repository
access, implementation or diffs. It received the required behavior and observable
contracts. This account is not a verbatim agent transcript.

The accepted model has two thin invocation hosts and one direct observation
script. Both hosts initialize the runtime/module and call Scheme main before the
clock. They time the unchanged bench(50) call and its success assertion, then
stop the clock, perform terminal resource cleanup and emit one JSON record.
Per-render file deletion, creation, formatting, writing and normal closing stay
inside the Scheme call. Process time separately spans subprocess launch through
exit. The fixed C provider is compiled as a separate non-LTO object without
pure/constant-return declarations, retaining opaque scalar imports.

The first explanation assumed a fully linked common Wasm module. The critique
corrected that assumption: native lowering and the Wasm runtime linker consume
the same optimized unlinked program. Wasm then links its Rust provider and runs
Binaryen again, while native links the shared Rust native archive. This comparison
includes those provider/optimization differences and cannot isolate collector or
foreign-call costs. Both final artifacts are rebuilt and identified separately.

The initial pair is excluded only from summaries: its raw outputs and image
checks are retained, and failure stops the campaign. Four retained alternating
pairs give each executor two first and two second positions. Every attempt uses
a fresh process/output directory. There are no retries, dropped failures or
removed outliers. Sources, tools, providers and artifacts are hashed before and
after. Unrelated system activity remains possible.

Full image equality checks the final result; it cannot alone establish that all
preceding renders execute. Separate traces of the exact native executable and
current linked V8 module establish 50 file opens/closes and 49 deletions. V8’s
separate iteration observer sees all 100 expected barriers. These diagnostics are
excluded from plain timing runs. Fine-grained counters from the earlier historical
V8 artifact are not attributed to this newly linked artifact.

The driver exposes preparation, process observation, validation and summary in
sequence. Its larger functions are complete evidence records, trial observations
and failure-preserving orchestration; splitting them into forwarding helpers
would obscure their boundary. The C main remains one atomic timer sequence so
setup, success checking and cleanup cannot be mistaken for timed work.
