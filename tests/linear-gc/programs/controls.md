# Bounded measurement controls

These patches deliberately remove correctness machinery. Apply them only in a
throwaway worktree of the optimization branch. They are not compiler options
and must never be applied to a production build.

`no-collection.patch` disables reclamation, including allocation-failure retries.
Build `runtime.sld` after applying it to measure allocation and root maintenance
without collection. Then apply `no-roots.patch` and rebuild to omit all generated
frames and root publications as well. The second patch is valid only while
collection is disabled. Both controls retain the original allocation sites,
layouts, bounds checks and function calls.

Use `programs/measure` with labels `linear-no-collection` and `linear-no-roots`.
Check every workload's checksum, and verify that its diagnostic collection count
is zero. The workloads terminate after a bounded allocation volume; these
controls consume much more memory because dead objects are never reclaimed.
Run one process at a time under an aggregate memory limit. A successful bounded
run is not evidence that the code is safe under collection or sustained use.

Compare the two controls to estimate root-maintenance cost with the same
nonreclaiming allocator. Compare them with the safe implementation cautiously:
never reclaiming changes memory growth, page faults and cache behavior, so the
result is not a strict performance lower bound. Subtracting measured GC pauses
is a separate, approximate model that holds the allocation schedule fixed.
Neither method predicts the effect of every possible future optimization.
