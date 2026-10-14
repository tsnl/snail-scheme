#!/usr/bin/env python3
"""Audit retained records and independently predict the canonical site counts."""

import copy
import gzip
import hashlib
import json
from pathlib import Path

import diagnose as d


# ---- A small scalar oracle retains totals, not a full-count trace ----


def predicted_bytes():
    state, total, sanity = 1, 0, []
    for test in range(1001):
        state = (701 * state + 743483) % 524288
        length = (state // 8) % (10 if test == 0 else 1000)
        total += length
        for _ in range(length):
            state = (701 * state + 743483) % 524288
            if test == 0:
                sanity.append((state // 8) % 128)
    d.require(sanity == [42, 16, 6, 43, 36, 0, 21], 'oracle sanity sequence differs')
    return total


def expected_counts():
    byte_count, roundtrips = predicted_bytes() * 100, 1001 * 100
    visits, decoding = byte_count + roundtrips, 2 * (byte_count + roundtrips)
    return dict(f101_entries=101, f99_entries=100100, f57_entries=200200, f79_entries=100100,
        f40_entries=visits, f93_entries=visits, f89_entries=visits, f59_entries=decoding,
        f67_entries=decoding, f74_entries=visits, f77_entries=visits,
        f89_capture_gets=5 * visits, f89_cell_gets=7 * visits, f89_signed_remainders=2 * visits,
        f89_signed_divisions=visits, f89_global_readiness_loads=0, f93_rng_closure_calls=byte_count,
        f99_rng_closure_calls=100000, f93_packed_writes=byte_count,
        f59_packed_reads=4 * byte_count, f67_packed_reads=4 * byte_count,
        f59_global_readiness_loads=8 * byte_count, f67_global_readiness_loads=8 * byte_count,
        f40_scalar_reads=2 * byte_count, f74_scalar_reads=byte_count, f77_scalar_reads=byte_count,
        f67_scalar_writes=2 * byte_count, array_type15_requests=2 * roundtrips,
        array_type29_requests=2 * roundtrips, array_type15_elements=2 * byte_count,
        array_type29_elements=2 * byte_count, array_type16_requests=0, array_type16_elements=0)


def audit_counts():
    actual, proof = d.load(d.BUILD / 'counters/counts.json'), d.load(d.BUILD / 'counter-erasure.json')
    d.require(set(actual) == {'setup', 'worker'}, 'unexpected counter scopes')
    for scope in actual.values():
        d.require(set(scope) == set(proof['boundaries']), 'counter names differ from source ledger')
        d.require(all(isinstance(value, str) and value.isdecimal() for value in scope.values()), 'invalid counter integer')
    worker = {name: int(value) for name, value in actual['worker'].items()}
    expected = expected_counts()
    d.require(all(worker[name] == value for name, value in expected.items()), 'canonical executed-site totals differ')
    d.require(all(value < 2 ** 63 for value in worker.values()), 'I64 counter overflow')
    return dict(expected_checked=expected, all_counter_names=len(worker), maximum_observed=max(worker.values()),
                bound='100 * 1001 roundtrips, <=999 bytes each; <=10 selected requests per byte in any one counter: <10^9 plus bounded setup',
                physical_allocation_claim=False, completion_counters=False)


# ---- Existing complete stream authority is reused unchanged ----


def audit_trace():
    path = d.copied(d.CASE + '/canonical-stream.bin.gz')
    raw = gzip.decompress(path.read_bytes())
    expected = '206b9db498985fcea1b6bdb458de81388a4c2e4f1a92418285b65562519fe35e'
    d.require(hashlib.sha256(raw).hexdigest() == expected, 'canonical internal trace changed')
    d.require(len(raw) // 4 == 7 * predicted_bytes() + 11 * 1001 + 2, 'trace fields disagree with independent counts')
    return dict(invocations=1, u32_fields=len(raw) // 4, sha256=expected,
                full100_internal_trace=False, per_invocation_generated_bytes=predicted_bytes())


# ---- Parser failures are explicit even under Python optimization ----


def rejected_profiles(profile):
    cases = []
    for label in ('missing-node', 'negative-delta', 'duplicate-node', 'boolean-id', 'nonfinite-time', 'empty-samples'):
        value = copy.deepcopy(profile)
        if label == 'missing-node':
            value['samples'][0] = 2 ** 32
        elif label == 'negative-delta':
            value['timeDeltas'][0] = -1
        elif label == 'duplicate-node':
            value['nodes'].append(value['nodes'][0])
        elif label == 'boolean-id':
            value['nodes'][0]['id'] = True
        elif label == 'nonfinite-time':
            value['endTime'] = float('nan')
        else:
            value['samples'], value['timeDeltas'] = [], []
        try:
            d.validate_profile(value)
        except ValueError:
            cases.append(label)
            continue
        raise ValueError('malformed profile accepted: ' + label)
    return cases


def audit_records():
    result = dict(identities=d.verify_inputs(), counter_audit=audit_counts(), reused_trace=audit_trace())
    for kind in ('profile', 'gc', 'native-stats', 'rust-profile', 'counters', 'rng-code'):
        record = d.load(d.BUILD / kind / 'attempt.json')
        d.require(record['status'] == 'valid' and record['valid_full_result'], 'incomplete diagnostic: ' + kind)
        d.require(record['returncode'] == 0 and record['cleanup']['live_members'] == [], 'nonterminal diagnostic: ' + kind)
    for kind in ('profile', 'rust-profile'):
        profile = d.load(d.BUILD / kind / 'profile.cpuprofile')
        d.validate_profile(profile)
        result[kind + '_malformed_inputs_rejected'] = rejected_profiles(profile)
    return result


if __name__ == '__main__':
    result = audit_records()
    d.save(Path(__file__).with_name('checks.json'), result)
    print('PASS identities, full results, independent site totals and malformed-profile rejection')
