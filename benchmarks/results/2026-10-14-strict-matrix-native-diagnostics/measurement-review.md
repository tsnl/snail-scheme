# Focused explanation and diagnostic review

The pinned simplify skill was applied to the newly written diagnostic runner,
counter source and evidence/audit modules. A fresh Sol 6.1 max behavioral
explainer received no history, implementation, files or diffs. It described an
evidence recorder around frozen invocation contracts, explicit instrumentation,
separate interpretation, bounded owned process groups, complete failure
retention and raw profiler windows. It did not claim to perform a code review.

The informed debate corrected an initial suggestion to validate a nonexistent
returned invocation field. The count is proved from the frozen native argv and
host specification; only the actual complete result and barrier schema is
checked. One process group suffices for perf and its child, provided the leader
is reaped and executing descendants are checked. Profiler intervals and native
whole-process statistics remain separate quantities. Broken callchain ancestry
is preserved but excluded from interpretation.

The lifecycle was strengthened so capture files and an initial record exist
before hash validation, and post-run audit failures cannot suppress cleanup or
raw capture persistence. The derived host and C transformation operation records
preparation failures and uses byte-exact source erasure. LLVM counter insertion
has its own erasure proof. Scalar counters never allocate Scheme objects, own
Scheme pointers, or callback into the guest. An initial LLVM erasure failure
and a perf extraction failure remain in evidence. The latter changed extraction
fields, not the selected profiler run.

After the first observation, targeted counters distinguished allocator requests,
metadata/zeroing operations, arrays, roots, calls and guards. A second counter
attempt added final constructor write widths after the parent asked for that
boundary. Independent type-layout arithmetic checks those totals. Original and
extended counters agree, and both sum to the original collector's process totals.

Longer-than-ten-line operations were inspected for cohesive guarantees:
`execute`/`reap_group` keep the bounded lifecycle and preservation transaction
together; result/profile handlers keep complete validation at their boundary;
binary-name readers expose bounded parsing; source-counter classification and
insertion are exhaustive concrete dispatch with the erasure proof beside them;
native source tables are explicit data; archive pack/restore/replay operations
keep membership, hash and execution obligations visible. The C counter writer
keeps a small fixed schema. No forwarding callback framework was introduced to
reduce line counts. Small identity, JSON, count and naming helpers retain one
useful guarantee.

The explanation pass stopped when source ownership, full-result semantics,
instrumentation effects and sampling limits were visible. Actual diagnostic
execution, explicit failure preservation, an audit under Python `-O`, complete
archive-byte verification and relocated full-count executions provide the
checks. There are no production changes; repository-wide compiler/runtime tests
are outside this report-only change's scope.
