# Measurement explanation and critique

The pinned [simplify skill](../../../.agents/skills/simplify/SKILL.md) was applied
to the narrow adaptation of the matched four-system measurement driver. The
fresh `/root/rust_mazefun_handoff/explain_mazefun_measurement` agent used
`gpt-6.1-sol`, reasoning `max`, and `fork_turns="none"`. It received the workload
and protocol contract in prose, with no repository files, implementation,
history, or tools. Its explanation and one informed critique preceded the
final driver freeze. The parent independently reviewed that frozen driver.

The explanation traced this sequence: freeze sources, tools, artifacts, inputs,
commands, and timer boundaries; validate output framing; obtain the coordinated
CPU hold; launch one excluded round and four cyclic retained rounds in fresh
processes and directories; persist raw bytes and terminal status before
validation; reject failures without replacements; verify all frozen identities;
then compute descriptive medians and ranges for each clock separately.

The critique led to exact framing checks for the actual Rust and Chez output,
duplicate-key rejection and numeric-type checks for strict JSON, durable
started-attempt records, raw-byte storage before decoding, and explicit launch
failure records without fabricated child stderr. The driver verifies the chain
from the byte-exact original input through the archived actual Chez decoder to
the strict specification's entire expected grid. Strict reads that specification
before its clock; all four processes receive the same original stdin bytes.

The review accepted the existing four-variant protocol without a general
measurement framework. The long contract, inventory, process transition, and
output-validation functions each expose one coherent operation; splitting them
to satisfy a line count would obscure the contract. No compiler or benchmark
source changes were needed for this measurement pass.

The owner rejected expanding the relocated correctness check into another
20-execution schedule. The explainer agreed that one full-count execution of
each restored variant verifies relocation; those durations remain outside the
clean samples. The archive preserves program inputs and evidence, while
external tools, dynamic libraries, Rust sysroot/dependencies, and the full
inherited environment remain bounded portability limits. The four retained
observations do not isolate representation, reference counting, collection,
code generation, or tiering as a causal mechanism.
