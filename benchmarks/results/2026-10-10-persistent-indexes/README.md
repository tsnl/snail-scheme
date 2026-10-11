# Persistent compiler evidence indexes

The expression-fact and constant-fold indexes map IR object identities to analysis
results. A persistent HAMT replaces their mutable hash tables: association returns
a new root and preserves every earlier version. The analyzer still assigns its
current root and updates counters. Its branch environments are separate.

| Compiler host | Mutable table | Persistent HAMT | Elapsed-time change |
| --- | ---: | ---: | ---: |
| Chibi | 14.044 s | 15.143 s | +7.8% |
| Snail Wasm / V8 | 7.650 s | 8.265 s | +8.0% |
| Snail native | 32.674 s | 31.873 s | -2.5% |

These are medians from three rotating measured rounds after one discarded
preliminary run, on logical CPU 2. Other task builds were paused. All 24 outputs
were byte-identical. Internal timers include parsing, library loading, analysis,
emission, tracing, and writing; executable preparation and process startup are
excluded. Unrelated system activity remains possible.

Persistence costs about 8% on Chibi and Wasm in this experiment. Treat native as
roughly comparable: its small median difference and the three-sample count do not
establish a reliable speedup. Chibi's last measured analysis stage takes 0.8 s
with the HAMT, versus 0.3 s with its native hash table. The recorded per-stage
times and all individual samples are in `results.json`.

## Representation and guarantees

[`identity-map.sld`](../../../src/snail-scheme/identity-map.sld) implements the
bitmap and packed-child layout described in
[Bagwell's *Ideal Hash Trees*](https://lampwww.epfl.ch/papers/idealhashtrees.pdf).
Three-bit hash digits keep each bitmap within one byte, so portable arithmetic
and a byte population-count table work on Chibi and both compiled hosts.

An update copies only the affected path. Fresh child vectors are initialized
before publication; existing nodes and vectors never change. Collision leaves
compare keys with `eq?`. A leaf stores the hash suffix left after its ancestors'
digits, avoiding an overflowing shift/divisor at the host's integer limit.
Keys and values remain shared Scheme objects; persistence preserves mappings.

Newest facts replace earlier facts for the same IR identity, including replacement
by unknown evidence. Fold conversion keeps the first alist entry, including false
and empty-list constants. Emission follows source traversal and never enumerates
the map. Saved-version tests compare updates against an alist reference model;
linked Wasm/native tests retain old roots across allocations and key mutation.

## Reproduce

The before compiler is integration revision `3505428`, equivalent in active
compiler source to review tip `29f6665`. The after compiler is `bef3c7c`; it was
prepared before committing, so its report records the preceding revision and a
dirty worktree. Its frozen source manifest exactly matches the committed source.
Both compile the same frozen before corpus.

`before-source.tar.gz` and `after-source.tar.gz` preserve the two implementations
and the input. `archives.json` records their SHA-256 digests. `results.json`
retains source manifests, build commands and logs, tool versions, compiler
artifact hashes, sample order, and output hashes. The unchanged maintained
`benchmarks/compare-compilers.py` matches the recorded measurement-runner digest.

Use two isolated worktrees of this review stack. Extract each source archive into
its worktree, then prepare the implementations in fresh output directories:

```sh
# In each worktree, after extracting its corresponding archive:
nix-shell benchmarks/shell.nix --run 'BINARYEN_CORES=1 python3 benchmarks/compile-self.py \
  --systems chibi snail-wasm snail-native --rounds 1 --cpu 2 \
  --timeout 600 --build-timeout 1500 --output build/prepared'

# After preparation finishes and other builds stop:
nix-shell benchmarks/shell.nix --run 'BINARYEN_CORES=1 python3 benchmarks/compare-compilers.py \
  --before /path/to/before/build/prepared --after /path/to/after/build/prepared \
  --output /tmp/snail-persistent-comparison --cpu 2 --rounds 3'
```

Choose a CPU in the host's allowed affinity set. The comparison verifies every
output against the frozen reference and checks both source manifests afterward.
