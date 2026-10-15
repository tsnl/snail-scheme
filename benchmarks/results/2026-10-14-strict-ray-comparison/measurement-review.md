# Measurement review

This is the parent's summary of a fresh Sol 6.1 max-effort behavioral
explanation and one informed critique, rather than a verbatim transcript.
The explainer received the workload, timing and evidence contract, without
repository access, existing implementation or inherited conversation history.

The accepted model is a frozen campaign containing fresh-process trials. Each
trial gets an initially absent canonical destination in its own working
directory. Record the process outcome before checking its clock, predicate and
complete output. Validate discarded runs identically. A failure stops and
preserves the campaign; it is never replaced with another sample.

The critique compared this model with the preceding Destruc measurement driver.
Its monotonic parent clock, fixed 900-second timeout, raw-before-validation
ordering and identity inventory were retained. Ray adds separate output
directories and complete image validation. All startup dependencies use
absolute paths; only the original relative output pathname depends on cwd.
Node coverage/debug variables are cleared along with NODE_OPTIONS. No such
variables or LD_PRELOAD were active in the observed launch environment.

The final image cannot prove prior renders occurred. Separate canonical
retained-work and file-lifecycle diagnostics supply that evidence. These
observers are absent from the timing commands. Normal per-render close is timed;
strict terminal cleanup and parent image hashing are outside the program clock.

The driver keeps contract/inventory data, one process observation and one
record-validation sequence together even when these operations exceed the
ten-line style target. Splitting them into numbered fragments would obscure
the order that makes a failed observation reviewable. No generic runner
framework or new production compiler behavior was introduced.

Four retained processes per implementation support median/range descriptions,
not significance or causal isolation. Different scene representations, helper
code, cleanup and compilers remain part of the measured complete programs.
