#!/usr/bin/env python3
"""Interpret sampled intervals and exact counters without making timing claims."""

from collections import Counter
import json
import math
from pathlib import Path
import re
import shutil
import tarfile

from diagnose import BUILD, OWNER, PLAN, REPORT, identity, load, save, verify_inputs


# ---- Samples have exclusive leaves and inclusive ancestors ----

def profile_tree(profile):
    nodes = {node['id']: node for node in profile['nodes']}
    assert len(nodes) == len(profile['nodes']) and nodes, 'duplicate or empty nodes'
    parents = {}
    for node in nodes.values():
        for child in node.get('children', []):
            assert child in nodes and child not in parents, 'invalid profile tree'
            parents[child] = node['id']
    assert len(profile['samples']) == len(profile['timeDeltas']) > 0
    assert all(sample in nodes for sample in profile['samples'])
    assert all(type(delta) is int and delta >= 0 for delta in profile['timeDeltas'])
    return nodes, parents


def frame_key(node):
    frame = node['callFrame']
    return tuple(frame[key] for key in ('functionName', 'url', 'scriptId', 'lineNumber', 'columnNumber'))


def sample_weights(profile, nodes, parents):
    exclusive, inclusive, hits = Counter(), Counter(), Counter()
    for sample, delta in zip(profile['samples'], profile['timeDeltas']):
        key = frame_key(nodes[sample])
        exclusive[key] += delta
        hits[key] += 1
        visited = set()
        while sample is not None:
            key = frame_key(nodes[sample])
            if key not in visited:  # Recursion does not count an interval twice per frame.
                inclusive[key] += delta
                visited.add(key)
            sample = parents.get(sample)
    return exclusive, inclusive, hits


def frame_rows(weights, hits, total, function_indices):
    return [dict(function=key[0], url=key[1], script=key[2], line=key[3], column=key[4],
                 wasm_function_index=function_indices.get(key[0]), leaf_samples=hits[key],
                 weighted_interval_us=weight, percent=100 * weight / total)
            for key, weight in weights.most_common()]


def function_map(name):
    path = BUILD / name / 'production.wat'
    text = path.read_text()
    imports = re.findall(r'^ \(import .*\(func \$([^\s()]+)', text, re.M)
    definitions = re.findall(r'^ \(func \$([^\s()]+)', text, re.M)
    names = imports + definitions
    assert len(names) == len(set(names)), 'duplicate function name'
    result = dict(disassembly=identity(path), imported_functions=len(imports),
                  functions=[dict(index=index, name=label) for index, label in enumerate(names)])
    save(BUILD / name / 'function-map.json', result)
    return {label: index for index, label in enumerate(names)}


def profile_summary(name, indices):
    path = BUILD / name / 'profile'
    profile, window = load(path / 'profile.cpuprofile'), load(path / 'profile-window.json')
    nodes, parents = profile_tree(profile)
    exclusive, inclusive, hits = sample_weights(profile, nodes, parents)
    total = sum(profile['timeDeltas'])
    ordered = [int(window[key]) for key in ('main_return_ns', 'start_submission_ns', 'start_acknowledgement_ns',
               'clock_start_ns', 'clock_stop_ns', 'stop_submission_ns', 'stop_completion_ns')]
    assert ordered == sorted(ordered) and total > 0
    return dict(raw_profile=identity(path / 'profile.cpuprofile'), samples=len(profile['samples']),
                profile_span_us=profile['endTime'] - profile['startTime'], weighted_interval_us=total,
                start_ack_after_submission_us=(ordered[2] - ordered[1]) / 1000,
                clock_after_ack_us=(ordered[3] - ordered[2]) / 1000,
                stop_submission_after_clock_us=(ordered[5] - ordered[4]) / 1000,
                stop_completion_after_submission_us=(ordered[6] - ordered[5]) / 1000,
                policy='Whole profiler interval weights; boundary intervals retained. Exclusive leaves and inclusive ancestors are distinct; inclusive recursion counts each complete frame at most once per sample. Unmapped Wasm names remain unresolved. These are sampled elapsed intervals, not continuously measured CPU time. Inspector and hrtime clocks are not aligned for clipping.',
                unresolved_wasm_names=sorted({key[0] for key in inclusive if key[1].startswith('wasm:') and key[0] not in indices}),
                exclusive=frame_rows(exclusive, hits, total, indices),
                inclusive=frame_rows(inclusive, hits, total, indices))


# ---- Service counters validate every unchanged worker through EOF and close ----

def validate_records(name):
    expected_count = 25 if name == 'sum1' else 2500
    for mode in ('profile', 'gc', 'counters', 'native-stats'):
        path = BUILD / name / mode
        record = load(path / 'attempt.json')
        assert record['returncode'] == 0 and record['valid_full_result'] and record['full_count'] == expected_count
        assert record['identities_before'] == record['identities_after'] == verify_inputs()
        for stream in ('stdout', 'stderr'):
            assert identity(path / (stream + '.bin'))['sha256'] == record[stream]['sha256']
        result = load(path / 'stdout.bin')
        assert result['result'] == 1 and math.isfinite(result['seconds']) and result['seconds'] > 0
        if mode == 'native-stats':
            assert result['setup_closed'] == 1 and result['worker_closed'] == expected_count and result['closed'] == expected_count + 1


def counter_summary(name):
    value = load(BUILD / name / 'counters/counts.json')
    workload = value['counts']['workload']
    workers = [file for file in value['files'] if file['phase'] == 'workload']
    count, characters, path = (25, 1100000, 'inputs/sum1.data') if name == 'sum1' else (2500, 28300, 'inputs/parsing.data')
    assert len(workers) == count and len(value['files']) == count + 1
    expected_peeks = 738998 if name == 'sum1' else 8175
    for file in workers:
        assert file['path'] == path and file['reads'] == characters + 1
        assert file['read_eof'] == 1 and file['peek_eof'] == 0 and file['closed']
        assert file['peeks'] == expected_peeks
    assert workload['snail:io/read-character'] == count * (characters + 1)
    return dict(raw_counts=identity(BUILD / name / 'counters/counts.json'),
                boundary='Identical frozen native-final Scheme module and provider; JS wrappers replace its direct scalar imports. Scalar call counts do not estimate production linked-machine-call overhead.',
                phases=value['counts'], full_count=count, identical_worker_records=True, worker=workers[0],
                scalar_calls=sum(value for key, value in workload.items() if key.startswith('snail:')),
                file_read_calls=workload['wasi:fd_read'], transferred_token_characters=workload['snail:datum/token-character'])


# ---- GC pauses and native allocations retain their different scopes ----

def gc_summary(name):
    value = load(BUILD / name / 'gc/gc-events.json')
    start, stop = value['markers']['clock_start_ms'], value['markers']['clock_stop_ms']
    events = [event for event in value['events'] if event['start_ms'] < stop and event['start_ms'] + event['duration_ms'] > start]
    return dict(raw_events=identity(BUILD / name / 'gc/gc-events.json'), total_events=len(value['events']),
                overlapping_events=len(events), duration_ms=sum(event['duration_ms'] for event in events),
                kinds=dict(Counter(event['detail']['kind'] for event in events)),
                policy='Observed events overlap the workload clock; whole event durations retained at boundaries. Occurrence and delivery timestamps are distinct. A missing event record is unavailable, not zero GC. Default heap policy. GC duration excludes mutator allocation, rooting, barriers and Rust allocator work; host activity was not quiet.')


def native_summary(name):
    path = BUILD / name / 'native-stats/stderr.bin'
    text = path.read_text()
    assert re.fullmatch(r'immix-gc .*\n', text)
    fields = dict(item.split('=', 1) for item in text.strip().split()[1:])
    values = {key: float(value) if key.endswith('_s') else int(value) if value.isdecimal() else value
              for key, value in fields.items()}
    return dict(raw_statistics=identity(path), statistics=values,
                scope='Unchanged frozen native binary; SNAIL_GC_STATS enables collection-phase clocks only. Whole process includes initialization and setup. Counts are native Scheme managed objects and requested bytes, not Rust allocations, V8 allocations, RSS or worker-only counts. Default collection policy retained.')


def preserve_inputs():
    plan, copied = load(PLAN), []
    paths = {PLAN}
    for name in ('sum1', 'read1'):
        for system in ('strict-v8', 'strict-v8-native-module', 'strict-native'):
            case = plan['systems'][name][system]
            paths.update(Path(arg) for arg in case['argv'] if arg.startswith(str(OWNER)))
            paths.add(Path(case['cwd']) / 'input.txt')
            paths.update((Path(case['cwd']) / 'inputs').glob('*'))
    for source in sorted(paths):
        target = BUILD / 'frozen' / source.relative_to(OWNER)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        assert identity(target)['sha256'] == identity(source)['sha256']
        copied.append(dict(original=identity(source), copy=str(target.relative_to(BUILD))))
    save(BUILD / 'frozen-identities.json', copied)


def package():
    preserve_inputs()
    files = sorted(path for path in BUILD.rglob('*') if path.is_file())
    entries = {str(path.relative_to(BUILD)): identity(path)['sha256'] for path in files}
    with tarfile.open(REPORT / 'artifacts.tar.xz', 'w:xz', preset=2) as archive:
        for path in files:
            item = archive.gettarinfo(str(path), arcname=str(path.relative_to(BUILD)))
            item.mtime, item.uid, item.gid, item.uname, item.gname = 0, 0, 0, '', ''
            with path.open('rb') as data:
                archive.addfile(item, data)
    save(REPORT / 'manifest.json', dict(archive=identity(REPORT / 'artifacts.tar.xz'), files=entries,
                                      analysis=identity(Path(__file__))))


def main():
    result = dict(clean_timing=False, frozen_inputs=verify_inputs(), workloads={})
    for name in ('sum1', 'read1'):
        validate_records(name)
        indices = function_map(name)
        result['workloads'][name] = dict(profile=profile_summary(name, indices), counters=counter_summary(name),
                                         gc=gc_summary(name), native=native_summary(name))
    save(REPORT / 'findings.json', result)
    package()
    print('PASS profile boundaries, full-count predicates, exact worker EOF cycles, GC scopes and all frozen identities')


if __name__ == '__main__':
    main()
