
// ---- Diagnostic cumulative phase snapshots ----

void native_diagnostic_gc_report(const char *phase) {
    fprintf(stderr, "gc phase=%s collections=%zu allocations=%zu bytes=%zu mark_s=%.9f sweep_s=%.9f "
            "arena_used=%zu live=%zu roots=%zu fields=%zu\n", phase, collections, allocated_objects,
            allocated_bytes, mark_seconds, sweep_seconds, used_blocks * BLOCK_SIZE,
            live_bytes, root_visits, field_visits);
}
