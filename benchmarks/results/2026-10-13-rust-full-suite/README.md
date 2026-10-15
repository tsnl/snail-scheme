# Complete Rust reference evidence

All 57 canonical workloads have Rust source implementations. The selected frozen
Node/Wasm artifacts pass 56 unchanged canonical inputs and iteration counts.
Recursive `ack` fails with the default Wasm stack; the successful
`ack --heap-frames` variant has a separate invocation and allocation policy.
These are correctness records. This archive adds no benchmark executions or
performance observations.

The source checkpoint is `f0cc1b1489bc0b0f8b43a6dac55ccae96fa4a670`; the original
R7RS suite revision is `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`.
[`manifest.json`](manifest.json) associates every workload with its selected
canonical report, Wasm hash and current Rust module hash. It preserves 23 original
reports and 1,675 original file paths in a content-addressed store of 479 verified
blobs. The files include frozen sources, Cargo inputs, hosts, Wasm and Chez
binaries, original inputs, checks and retained-work evidence.

[`artifacts.tar.xz`](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-13-rust-full-suite/artifacts.tar.xz) is 4,001,220 bytes and has SHA-256
`61f495a71b5a8a6aed43d9f58d4d73b3dbaffab79c468c9998c6a22029030d54`.
[`replay-check.json`](replay-check.json) records verification of every stored
blob. The archive contains `manifest.json` and `blobs/<sha256>`; repeated source,
input and host snapshots share a blob without changing their historical paths.
The separately committed archives listed in `reused_archives` retain complete
generated-file, graph, compiler-word and review evidence. Their hashes and contents
are unchanged. The historical five-case timing report remains separate.

Current sources and the sources that produced a selected artifact are distinct
records. Some artifacts predate later shared reader changes or test-only review
commits. Their original reports and frozen source snapshots remain authoritative
for those binaries. Older build records lack a full inherited environment and
verbose compiler command line; this archive does not infer the absence of build
overrides. Allocation, sharing, continuation and checked-domain adaptations are
documented in [the port contracts](../../wasm-reference/PORTING.md). Independent
reviews of the linked-list, later structural and SLaTeX cohorts remain pending.

Extract to a new directory and verify the blobs without executing a workload:

```sh
mkdir -p /tmp/rust-reference-evidence
tar -xJf benchmarks/results/2026-10-13-rust-full-suite/artifacts.tar.xz \
  -C /tmp/rust-reference-evidence
python3 - <<'PY'
import hashlib
import json
from pathlib import Path

root = Path('/tmp/rust-reference-evidence')
manifest = json.loads((root / 'manifest.json').read_text())
for digest, size in manifest['blobs'].items():
    data = (root / 'blobs' / digest).read_bytes()
    assert len(data) == size and hashlib.sha256(data).hexdigest() == digest
for digest in manifest['mapped_files'].values():
    assert digest in manifest['blobs']
print(f"Verified {len(manifest['blobs'])} blobs and {len(manifest['cases'])} cases")
PY
```

To inspect or relocate an original file, look up its unchanged absolute path in
`mapped_files` and copy the corresponding verified blob to a chosen destination.
Do not overwrite historical paths. A measurement harness must separately restore
each case's original stdin, data files, host invocation and timer/predicate
boundaries; the content store itself does not start a timing campaign.
