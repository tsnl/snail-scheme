#!/usr/bin/env python3
"""Separate full bv2string sampling, GC events and native collector counters."""

import argparse
from collections import defaultdict
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import time


# ---- Frozen inputs and diagnostic scope ----

ROOT = Path(__file__).resolve().parents[3]
BUILD = ROOT / 'build/bv2string-diagnostics'
OWNER = '/tmp/snail-strict-bv2string-20261014'
PREPARATION = OWNER + '/build/bv2string-attempt4'
CASE = PREPARATION + '/bv2string'
PLAN = OWNER + '/benchmarks/results/2026-10-14-strict-bv2string-preparation/timing-plan.json'
REMOVED = ('NODE_OPTIONS', 'NODE_V8_COVERAGE', 'NODE_DEBUG', 'NODE_DEBUG_NATIVE',
           'LD_PRELOAD', 'SNAIL_NATIVE_GC_INTERVAL', 'SNAIL_GC_STATS',
           'SNAIL_GC_HEAP_BYTES', 'SNAIL_GC_MIN_BYTES')


def load(path):
    return json.loads(Path(path).read_text())


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def identity(path):
    return dict(path=str(path), sha256=hashlib.sha256(Path(path).read_bytes()).hexdigest())


def copied(path):
    return BUILD / 'inputs/files' / str(path).lstrip('/')


def verify_inputs():
    manifest, plan = load(BUILD / 'input-manifest.json'), load(copied(PLAN))
    for leaf, expected in manifest['files'].items():
        require(identity(BUILD / 'inputs' / leaf)['sha256'] == expected, 'copied identity changed: ' + leaf)
    for path, expected in plan['identities'].items():
        actual = copied(path) if path.startswith(OWNER + '/') else Path(path)
        require(identity(actual)['sha256'] == expected, 'frozen clean identity changed: ' + path)
    require(plan['cpu'] in os.sched_getaffinity(0), 'requested CPU unavailable')
    return dict(copied_files=len(manifest['files']), clean_identities=len(plan['identities']), unchanged=True)


# ---- Additions erase exactly to the measured hosts ----

PROFILE_HEADER = '''import inspector from 'node:inspector';
const diagnosticsSession = new inspector.Session();
diagnosticsSession.connect();
const diagnosticsMarkers = {clock_domain: 'process.hrtime.bigint nanoseconds', sampling_interval_us: 1000};
const profiler = (method, parameters = {}) => new Promise((resolve, reject) => {
  diagnosticsSession.post(method, parameters, (error, value) => error ? reject(error) : resolve(value));
});
'''
PROFILE_START = '''await profiler('Profiler.enable');
await profiler('Profiler.setSamplingInterval', {interval: 1000});
diagnosticsMarkers.start_submission_ns = process.hrtime.bigint().toString();
await profiler('Profiler.start');
diagnosticsMarkers.start_acknowledgement_ns = process.hrtime.bigint().toString();
'''
PROFILE_STOP = '''const diagnosticsClockStop = process.hrtime.bigint();
const seconds = Number(diagnosticsClockStop - start) / 1e9;
diagnosticsMarkers.clock_start_ns = start.toString();
diagnosticsMarkers.clock_stop_ns = diagnosticsClockStop.toString();
diagnosticsMarkers.stop_submission_ns = process.hrtime.bigint().toString();
const diagnosticsProfile = (await profiler('Profiler.stop')).profile;
diagnosticsMarkers.stop_completion_ns = process.hrtime.bigint().toString();
diagnosticsSession.disconnect();
fs.writeFileSync(process.argv[5] + '/profile.cpuprofile', JSON.stringify(diagnosticsProfile));
fs.writeFileSync(process.argv[5] + '/profile-window.json', JSON.stringify(diagnosticsMarkers));'''

GC_HEADER = '''import { PerformanceObserver, performance, constants } from 'node:perf_hooks';
const diagnosticsEvents = [], diagnosticsBatches = [], diagnosticsMarkers = {clock_domain: 'performance.now milliseconds'};
const collectGC = (entries, delivery) => {
  const deliveredAt = performance.now();
  diagnosticsBatches.push({delivery, delivered_at_ms: deliveredAt, entries: entries.length});
  for (const entry of entries) diagnosticsEvents.push({name: entry.name, entry_type: entry.entryType,
    start_ms: entry.startTime, duration_ms: entry.duration, detail: entry.detail, delivered_at_ms: deliveredAt});
};
const diagnosticsObserver = new PerformanceObserver(list => collectGC(list.getEntries(), 'callback'));
'''
GC_START = '''diagnosticsObserver.observe({entryTypes: ['gc']});
diagnosticsMarkers.observer_started_ms = performance.now();
diagnosticsMarkers.clock_start_ms = performance.now();
'''
GC_STOP = '''const diagnosticsClockStop = process.hrtime.bigint();
const seconds = Number(diagnosticsClockStop - start) / 1e9;
diagnosticsMarkers.clock_stop_ms = performance.now();
diagnosticsMarkers.clock_start_ns = start.toString();
diagnosticsMarkers.clock_stop_ns = diagnosticsClockStop.toString();
diagnosticsMarkers.drain_started_ms = performance.now();
await new Promise(resolve => setImmediate(resolve));
await new Promise(resolve => setImmediate(resolve));
collectGC(diagnosticsObserver.takeRecords(), 'takeRecords');
diagnosticsMarkers.drain_stopped_ms = performance.now();
diagnosticsObserver.disconnect();
fs.writeFileSync(process.argv[5] + '/gc-events.json', JSON.stringify({markers: diagnosticsMarkers,
  batches: diagnosticsBatches, events: diagnosticsEvents, constants}));'''


def changed_host(original_path, target, changes):
    original, text = original_path.read_text(), original_path.read_text()
    for before, after in changes:
        require(text.count(before) == 1, 'host replacement is not unique: ' + before)
        text = text.replace(before, after)
    restored = text
    for before, after in reversed(changes):
        require(restored.count(after) == 1, 'host erasure is not unique: ' + after)
        restored = restored.replace(after, before)
    require(restored == original, 'host additions failed exact erasure')
    target.write_text(text)
    save(target.with_suffix('.proof.json'), dict(original=identity(original_path), derived=identity(target),
         exact_source_erasure=True, changes=changes, guest_changes=False))


def make_host(kind):
    header, start, stop = (PROFILE_HEADER, PROFILE_START, PROFILE_STOP) if kind == 'profile' else (GC_HEADER, GC_START, GC_STOP)
    changes = [('import fs', header + 'import fs'),
               ('instance.exports.main();', 'instance.exports.main();\ndiagnosticsMarkers.main_return_ns = process.hrtime.bigint().toString();'),
               ('const start = process.hrtime.bigint();', start + 'const start = process.hrtime.bigint();'),
               ('const seconds = Number(process.hrtime.bigint() - start) / 1e9;', stop)]
    target = BUILD / (kind + '-host.mjs')
    changed_host(copied(PREPARATION + '/host.mjs'), target, changes)
    return target


# ---- A bounded process owns regular capture files and all group members ----


def group_members(group):
    members = []
    for entry in Path('/proc').iterdir():
        if not entry.name.isdecimal():
            continue
        try:
            fields = (entry / 'stat').read_text().rpartition(') ')[2].split()
            if int(fields[2]) == group:
                members.append(dict(pid=int(entry.name), state=fields[0]))
        except (OSError, IndexError, ValueError):
            continue
    return members


def stop_group(child):
    before = group_members(child.pid)
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    child.wait(timeout=10)
    deadline = time.monotonic() + 10
    after = group_members(child.pid)
    while any(member['state'] not in ('Z', 'X') for member in after):
        if time.monotonic() >= deadline:
            raise RuntimeError('live owned descendants after SIGKILL: ' + repr(after))
        time.sleep(0.01)
        after = group_members(child.pid)
    return dict(before=before, after=after, live_members=[], zombies_dead_not_running=True)


def wait_bounded(child, directory, deadline):
    while child.poll() is None:
        if time.monotonic() >= deadline:
            return 'timeout'
        if any((directory / name).stat().st_size > 16 * 1024 * 1024 for name in ('stdout.bin', 'stderr.bin')):
            return 'capture-limit'
        time.sleep(0.02)
    return 'exited'


def execute(command, directory, environment=None, stdin=None):
    # One transaction keeps launch, capture, raw persistence and group cleanup together.
    env = {k: v for k, v in os.environ.items() if k not in REMOVED}
    env.update(environment or {})
    record = dict(command=list(map(str, command)), cwd=str(directory), status='started', clean_timing=False,
                  started_utc=datetime.now(timezone.utc).isoformat(), timeout_seconds=120,
                  driver=identity(Path(__file__)),
                  environment={name: env.get(name) for name in (*REMOVED, 'LD_LIBRARY_PATH', 'LANG', 'LC_ALL', 'TZ')},
                  identities_before=verify_inputs())
    path, child, started = directory / 'attempt.json', None, time.monotonic()
    save(path, record)
    (directory / 'stdin.bin').write_bytes(stdin or b'')
    try:
        with (directory / 'stdin.bin').open('rb') as input_file, (directory / 'stdout.bin').open('wb') as out, (directory / 'stderr.bin').open('wb') as err:
            child = subprocess.Popen(record['command'], cwd=directory, env=env, stdin=input_file,
                                     stdout=out, stderr=err, start_new_session=True)
            record.update(pid=child.pid, process_group=child.pid, status='running')
            save(path, record)
            record['status'] = wait_bounded(child, directory, started + 120)
    except BaseException as error:
        record.update(status='failed', error=repr(error))
        raise
    finally:
        if child is not None:
            try:
                record['cleanup'] = stop_group(child)
                record['returncode'] = child.returncode
            except BaseException as error:
                record['cleanup_error'] = repr(error)
        record.update(diagnostic_process_seconds=time.monotonic() - started,
                      stdout_raw=identity(directory / 'stdout.bin'), stderr_raw=identity(directory / 'stderr.bin'),
                      identities_after=verify_inputs())
        save(path, record)
    record.update(stdout=(directory / 'stdout.bin').read_text(), stderr=(directory / 'stderr.bin').read_text())
    save(path, record)
    return record


# ---- Full result validation precedes diagnostic interpretation ----


def require_success(record):
    require(record['status'] == 'exited' and record['returncode'] == 0, 'process failed or exceeded its bound')
    require(record.get('cleanup', {}).get('live_members') == [], 'owned process group cleanup failed')
    require(record['identities_before'] == record['identities_after'], 'frozen identity verification changed')


def gc_summary(path):
    value = load(path)
    start, stop = value['markers']['clock_start_ms'], value['markers']['clock_stop_ms']
    overlap = [event for event in value['events'] if event['start_ms'] < stop and
               event['start_ms'] + event['duration_ms'] > start]
    return dict(observed_events=len(value['events']), overlapping_events=len(overlap),
                whole_overlapping_duration_ms=sum(event['duration_ms'] for event in overlap),
                window_ms=stop - start, kind_counts={str(kind): sum(event['detail']['kind'] == kind for event in overlap)
                for kind in sorted({event['detail']['kind'] for event in overlap})},
                policy='classify by start/duration, retain crossing events whole; bounded drain is not proof of complete delivery')


def validate_snail(record, native=False):
    require_success(record)
    require(record['stdout'].endswith('\n') and len(record['stdout'].splitlines()) == 1, 'unexpected stdout framing')
    result = json.loads(record['stdout'])
    expected = dict(result=1, barriers=0) if native else dict(result='1', barriers=None, setup_barriers=None)
    require(set(result) == set(expected) | {'seconds'}, 'unexpected result fields')
    require(all(type(result[name]) is type(value) and result[name] == value for name, value in expected.items()), 'full predicate or barrier result differs')
    require(type(result['seconds']) in (int, float) and math.isfinite(result['seconds']) and result['seconds'] > 0, 'invalid diagnostic clock')
    record.update(valid_full_result=True, diagnostic_workload_seconds=result['seconds'], full_count=100)


def profile_nodes(profile):
    nodes = {}
    require(isinstance(profile.get('nodes'), list), 'profile nodes must be an array')
    for node in profile['nodes']:
        require(isinstance(node, dict) and type(node.get('id')) is int and node['id'] > 0 and node['id'] not in nodes, 'invalid/duplicate profile node ID')
        frame = node.get('callFrame')
        require(isinstance(frame, dict), 'missing profile call frame')
        require(all(isinstance(frame.get(key), str) for key in ('functionName', 'url', 'scriptId')), 'invalid frame strings')
        require(all(type(frame.get(key)) is int and frame[key] >= -1 for key in ('lineNumber', 'columnNumber')), 'invalid frame coordinates')
        nodes[node['id']] = node
    return nodes


def validate_profile(profile):
    require(isinstance(profile, dict), 'profile must be an object')
    nodes = profile_nodes(profile)
    require(isinstance(profile.get('samples'), list) and isinstance(profile.get('timeDeltas'), list), 'missing profile samples/deltas')
    require(len(profile['samples']) == len(profile['timeDeltas']) > 0, 'profile samples/deltas differ or are empty')
    require(all(type(sample) is int and sample in nodes for sample in profile['samples']), 'unknown/noninteger sample node')
    require(all(type(delta) is int and delta >= 0 for delta in profile['timeDeltas']), 'invalid/negative profile delta')
    require(all(type(profile.get(key)) in (int, float) and math.isfinite(profile[key]) for key in ('startTime', 'endTime')), 'invalid profile timestamps')
    require(profile['endTime'] >= profile['startTime'] and sum(profile['timeDeltas']) > 0, 'invalid profile interval')
    return nodes


def profile_summary(path):
    profile = load(path)
    nodes = validate_profile(profile)
    weights, hits = defaultdict(int), defaultdict(int)
    for sample, delta in zip(profile['samples'], profile['timeDeltas']):
        frame = nodes[sample]['callFrame']
        key = (frame['functionName'], frame['url'], frame['scriptId'], frame['lineNumber'], frame['columnNumber'])
        weights[key] += delta
        hits[key] += 1
    rows = [dict(function=key[0], url=key[1], script=key[2], line=key[3], column=key[4],
                 samples=hits[key], weighted_interval_us=weight) for key, weight in weights.items()]
    return dict(samples=len(profile['samples']), weighted_interval_us=sum(profile['timeDeltas']),
                profile_span_us=profile['endTime'] - profile['startTime'],
                first_delta_us=profile['timeDeltas'][0], last_delta_us=profile['timeDeltas'][-1],
                policy='exclusive leaf intervals merged by complete frame; boundary intervals retained whole; not continuous CPU execution',
                frames=sorted(rows, key=lambda row: row['weighted_interval_us'], reverse=True))


def run_host(kind):
    directory = BUILD / kind
    directory.mkdir(exist_ok=False)
    plan = load(copied(PLAN))
    command = [plan['taskset'], '-c', str(plan['cpu']), plan['systems']['strict-v8']['argv'][0],
               str(make_host(kind)), str(copied(CASE + '/strict.wasm')), str(copied(CASE + '/spec.json')),
               '--diagnostics', str(directory)]
    record = execute(command, directory)
    try:
        validate_snail(record)
        require(not record['stderr'], 'guest wrote stderr')
        if kind == 'profile':
            record['profile'] = identity(directory / 'profile.cpuprofile')
            record['window'] = load(directory / 'profile-window.json')
            save(directory / 'summary.json', profile_summary(directory / 'profile.cpuprofile'))
        else:
            record['gc_events'] = identity(directory / 'gc-events.json')
            save(directory / 'summary.json', gc_summary(directory / 'gc-events.json'))
        record['status'] = 'valid'
    except BaseException as error:
        record['validation_error'] = repr(error)
        raise
    finally:
        save(directory / 'attempt.json', record)
    print(kind, 'PASS full100; original optimized guest unchanged; diagnostic only', flush=True)


def run_native_stats():
    directory = BUILD / 'native-stats'
    directory.mkdir(exist_ok=False)
    plan = load(copied(PLAN))
    command = [plan['taskset'], '-c', str(plan['cpu']), copied(CASE + '/timing-native/native'), '100']
    record = execute(command, directory, {'SNAIL_GC_STATS': '1'})
    try:
        validate_snail(record, native=True)
        require(re.fullmatch(r'immix-gc .*\n', record['stderr']) is not None, 'unexpected native stats framing')
        fields = dict(item.split('=', 1) for item in record['stderr'].strip().split()[1:])
        record['gc_statistics'] = {name: float(value) if name.endswith('_s') else int(value) if value.isdecimal() else value
                                   for name, value in fields.items()}
        record['scope'] = 'whole process including initialization; bytes requested by collector, not RSS; GC clock reads enabled'
        record['status'] = 'valid'
    except BaseException as error:
        record['validation_error'] = repr(error)
        raise
    finally:
        save(directory / 'attempt.json', record)
    print('native-stats PASS full100; unchanged binary, default collector policy', flush=True)


# ---- Rust samples enclose synchronous WASI start, beyond its internal clock ----


def run_rust_profile():
    directory = BUILD / 'rust-profile'
    directory.mkdir(exist_ok=False)
    header = PROFILE_HEADER.replace('1000', '100') + "import fs from 'node:fs';\n"
    start = PROFILE_START.replace('1000', '100')
    stop = PROFILE_STOP.replace("process.argv[5] + '/profile.cpuprofile'", "new URL('./rust-profile/profile.cpuprofile', import.meta.url)")
    stop = stop.replace("process.argv[5] + '/profile-window.json'", "new URL('./rust-profile/profile-window.json', import.meta.url)")
    worker = 'process.exitCode = wasi.start(instance);'
    text = start + 'const start = process.hrtime.bigint();\n' + worker + '\n' + stop
    host = BUILD / 'rust-profile-host.mjs'
    changed_host(copied(CASE + '/rust-reference/run-wasi.mjs'), host,
                 [('import { readFile }', header + 'import { readFile }'), (worker, text)])
    plan = load(copied(PLAN))
    command = [plan['taskset'], '-c', str(plan['cpu']), plan['systems']['strict-v8']['argv'][0],
               '--disable-warning=ExperimentalWarning', host, copied(CASE + '/rust-reference/bv2string.wasm')]
    record = execute(command, directory, stdin=copied(CASE + '/input.txt').read_bytes())
    try:
        require_success(record)
        require(not record['stderr'], 'Rust guest wrote stderr')
        match = re.fullmatch(r'Result: 0\n\+!CSVLINE!\+rust-wasm,bv2string:100,([0-9.eE+\-]+)\n', record['stdout'])
        require(match is not None, 'Rust full-count result/framing differs')
        seconds = float(match[1])
        require(math.isfinite(seconds) and seconds > 0, 'invalid Rust diagnostic clock')
        record['diagnostic_workload_seconds'] = seconds
        record.update(valid_full_result=True, full_count=100, scope='WASI.start includes input, workload, predicate, reporting and exit')
        record['profile'] = identity(directory / 'profile.cpuprofile')
        record['window'] = load(directory / 'profile-window.json')
        save(directory / 'summary.json', profile_summary(directory / 'profile.cpuprofile'))
        record['status'] = 'valid'
    except BaseException as error:
        record['validation_error'] = repr(error)
        raise
    finally:
        save(directory / 'attempt.json', record)
    print('rust-profile PASS full100; unchanged optimized guest; broader WASI-start scope', flush=True)


# ---- Separate site counters preserve operand order and reference storage ----


def expression(text, start):
    depth = 0
    for index in range(start, len(text)):
        if text[index] == '(':
            depth += 1
        elif text[index] == ')':
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    raise ValueError('unclosed expression')


class CounterText:
    def __init__(self, original):
        self.original, self.text, self.changes, self.names = original, original, [], {}

    def increment(self, name, amount='(i64.const 1)'):
        self.names[name] = 'I64; operation request before operands; array requests/elements after length operand, before allocation'
        return f'(global.set $bv_{name} (i64.add (global.get $bv_{name}) {amount}))'

    def replace(self, before, after):
        require(self.text.count(before) == 1, 'counter replacement is not unique')
        self.text = self.text.replace(before, after)
        self.changes.append([before, after])


def operation_counter(name, prefix):
    categories = [(r'array\.get_u \$type29', 'packed_reads', 'i32'),
                  (r'array\.get \$type15', 'scalar_reads', 'i32'),
                  (r'array\.set \$type29', 'packed_writes', None),
                  (r'array\.set \$type15', 'scalar_writes', None),
                  (r'i64\.rem_s', 'signed_remainders', 'i64'), (r'i64\.div_s', 'signed_divisions', 'i64'),
                  (r'i32\.wrap_i64', 'index_or_byte_narrowings', 'i32'),
                  (r'global\.get \$ready\d+', 'global_readiness_loads', 'i32'),
                  (r'i32\.eqz', 'zero_predicates', 'i32'),
                  (r'i64\.(?:gt|ge|lt|le)_[us]', 'ordered_i64_predicates', 'i32'),
                  (r'call_ref \$call42', 'rng_closure_calls', 'i64')]
    for pattern, category, result in categories:
        if re.fullmatch(pattern, prefix):
            return f'f{name}_{category}', result
    if name == 89 and prefix.startswith('struct.get '):
        _, type_name, field = prefix.split()
        result = '(ref $type65)' if type_name == '$environment89' and field == '1' else '(ref $type64)' if type_name == '$environment89' and field in ('2', '3', '4') else '(ref $type63)' if type_name == '$environment89' else '(ref $type66)' if type_name == '$type65' else 'i64'
        return 'f89_capture_gets' if type_name == '$environment89' else 'f89_cell_gets', result
    return None


def counted_operations(text, name, counters):
    pattern = r'\((array\.(?:get_u|get|set) \$\w+|i64\.(?:rem_s|div_s)|i32\.(?:wrap_i64|eqz)|global\.get \$ready\d+|i64\.(?:gt|ge|lt|le)_[us]|call_ref \$call42|struct\.get \$\w+ \d+)(?=\s|\))'
    for match in reversed(list(re.finditer(pattern, text))):
        selected = operation_counter(name, match[1])
        if selected is None:
            continue
        counter, result = selected
        original = expression(text, match.start())
        block_type = f' (result {result})' if result else ''
        after = f'(block{block_type} {counters.increment(counter)} {original})'
        text = text[:match.start()] + after + text[match.start() + len(original):]
    return text


def counted_constructors(text, counters):
    # One fresh I32 local retains the evaluated length; no diagnostic reference local.
    for match in reversed(list(re.finditer(r'\(array\.new_default (\$\w+)(?=\s)', text))):
        original, type_name = expression(text, match.start()), match[1]
        category = 'array_' + type_name[1:]
        length = original[len(match[0]):].strip()[:-1].strip()
        size = f'(block (result i32) (local.set $bv_length {length}) {counters.increment(category + "_requests")} {counters.increment(category + "_elements", "(i64.extend_i32_u (local.get $bv_length))")} (local.get $bv_length))'
        after = f'(array.new_default {type_name} {size})'
        text = text[:match.start()] + after + text[match.start() + len(original):]
    return text


def make_counter_wat(original):
    counters = CounterText(original)
    hot = {40, 57, 59, 67, 74, 77, 79, 89, 93, 99, 101}
    for match in list(re.finditer(r'\n \(func \$function(\d+) ', original)):
        name, before = int(match[1]), expression(original, match.start() + 2)
        after = counted_operations(before, name, counters) if name in hot else before
        if '(array.new_default ' in before or '(struct.new ' in before:
            after = counted_constructors(after, counters)
        additions = []
        if '(array.new_default ' in before:
            additions.append('(local $bv_length i32)')
        if name in hot:
            additions.append(counters.increment(f'f{name}_entries'))
        if additions:
            lines, index = after.splitlines(keepends=True), 1
            while lines[index].startswith('  (local '):
                index += 1
            after = ''.join(lines[:index] + ['  ' + line + '\n' for line in additions] + lines[index:])
        if before != after:
            counters.replace(before, after)
    additions = ''.join(f' (global $bv_{name} (mut i64) (i64.const 0))\n (export "__diag_{name}" (global $bv_{name}))\n' for name in sorted(counters.names))
    require(counters.text.rstrip().endswith(')'), 'unexpected final WAT module delimiter')
    closing = counters.text.rfind(')')
    counters.replace(counters.text, counters.text[:closing] + additions + counters.text[closing:])
    restored = counters.text
    for before, after in reversed(counters.changes):
        require(restored.count(after) == 1, 'counter erasure is not unique')
        restored = restored.replace(after, before)
    require(restored == original, 'counter additions failed exact original WAT erasure')
    return counters


def run_counters():
    directory = BUILD / 'counters'
    directory.mkdir(exist_ok=False)
    original_path = copied(CASE + '/strict.optimized.wat')
    counters = make_counter_wat(original_path.read_text())
    wat = BUILD / 'counters.wat'
    wat.write_text(counters.text)
    save(BUILD / 'counter-erasure.json', dict(original=identity(original_path), derived=identity(wat),
         exact_source_erasure=True, fresh_locals='I32 only; no new reference storage',
         boundaries=counters.names, changes=counters.changes,
         limits='post-optimization instrumentation; V8 JIT and physical lifetimes can differ; no timing comparisons'))
    tool = '/nix/store/nd1279k2zlbp23gfqcl0qp5xk40xlxr8-binaryen-132/bin/wasm-as'
    assembly = BUILD / 'counter-assembly'
    assembly.mkdir(exist_ok=False)
    module = BUILD / 'counters.wasm'
    # Match production features; --all-features enables unrelated exact-reference proposals.
    features = ['--mvp-features', '--enable-gc', '--enable-reference-types', '--enable-tail-call',
                '--enable-mutable-globals', '--enable-sign-ext', '--enable-bulk-memory',
                '--enable-nontrapping-float-to-int']
    built = execute([tool, '-g', *features, wat, '-o', module], assembly, {'BINARYEN_CORES': '1'})
    require_success(built)
    require(not built['stderr'], 'assembler wrote stderr')
    header = '''const diagnosticsCounters = () => Object.fromEntries(Object.entries(instance.exports)
  .filter(([name]) => name.startsWith('__diag_')).map(([name, value]) => [name.slice(7), value.value.toString()]));
const diagnosticsSetup = diagnosticsCounters();
for (const [name, value] of Object.entries(instance.exports)) if (name.startsWith('__diag_')) value.value = 0n;
'''
    original = copied(PREPARATION + '/host.mjs')
    host = BUILD / 'counters-host.mjs'
    changed_host(original, host, [('barriers = 0;\nconst start', header + 'barriers = 0;\nconst start'),
         ('if (mode === \'--validate\') assert.equal(barriers,',
          "fs.writeFileSync(process.argv[5] + '/counts.json', JSON.stringify({setup: diagnosticsSetup, worker: diagnosticsCounters()}));\nif (mode === '--validate') assert.equal(barriers,")])
    plan = load(copied(PLAN))
    command = [plan['taskset'], '-c', str(plan['cpu']), plan['systems']['strict-v8']['argv'][0],
               host, module, copied(CASE + '/spec.json'), '--diagnostics', directory]
    record = execute(command, directory)
    try:
        validate_snail(record)
        require(not record['stderr'], 'counter guest wrote stderr')
        record.update(counter_module=identity(module), counts=identity(directory / 'counts.json'), status='valid')
    except BaseException as error:
        record['validation_error'] = repr(error)
        raise
    finally:
        save(directory / 'attempt.json', record)
    print('counters PASS full100; exact original WAT erasure; separate heavily instrumented guest', flush=True)


# ---- Exact binary function indices select a bounded V8 machine-code dump ----


def uleb(data, position):
    value, shift = 0, 0
    while True:
        require(position < len(data) and shift < 35, 'invalid binary ULEB32')
        byte = data[position]
        position += 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, position
        shift += 7


def name_string(data, position):
    length, position = uleb(data, position)
    require(position + length <= len(data), 'truncated binary name')
    return data[position:position + length].decode('utf-8'), position + length


def function_names(data):
    require(data[:8] == b'\0asm\1\0\0\0', 'invalid Wasm header')
    position, names = 8, {}
    while position < len(data):
        section, position = data[position], position + 1
        size, position = uleb(data, position)
        end = position + size
        require(end <= len(data), 'truncated binary section')
        if section == 0:
            label, cursor = name_string(data, position)
            if label == 'name':
                names.update(function_name_section(data[cursor:end]))
        position = end
    return names


def function_name_section(data):
    position, names = 0, {}
    while position < len(data):
        subsection, position = data[position], position + 1
        size, position = uleb(data, position)
        end = position + size
        require(end <= len(data), 'truncated name subsection')
        if subsection == 1:
            count, cursor = uleb(data, position)
            for _ in range(count):
                index, cursor = uleb(data, cursor)
                name, cursor = name_string(data, cursor)
                require(index not in names and cursor <= end, 'duplicate/truncated function name')
                names[index] = name
            require(cursor == end, 'trailing function-name bytes')
        position = end
    return names


def run_rng_code():
    directory = BUILD / 'rng-code'
    directory.mkdir(exist_ok=False)
    names = function_names(copied(CASE + '/strict.wasm').read_bytes())
    indices = [index for index, name in names.items() if name == 'function89']
    require(len(indices) == 1, 'RNG function name does not select one binary index')
    save(directory / 'function-map.json', dict(names=names, selected_function='function89', selected_index=indices[0]))
    plan = load(copied(PLAN))
    command = [plan['taskset'], '-c', str(plan['cpu']), plan['systems']['strict-v8']['argv'][0],
               f'--print-wasm-code-function-index={indices[0]}',
               copied(PREPARATION + '/host.mjs'), copied(CASE + '/strict.wasm'), copied(CASE + '/spec.json')]
    record = execute(command, directory)
    try:
        require_success(record)
        require(not record['stderr'], 'machine-code run wrote stderr')
        rows = [line for line in record['stdout'].splitlines() if line.startswith('{"seconds":')]
        require(len(rows) == 1, 'machine-code output has missing/duplicate full result')
        validate_snail({**record, 'stdout': rows[0] + '\n'})
        require('function89' in record['stdout'], 'selected function absent from printed code')
        record.update(valid_full_result=True, full_count=100, selected_index=indices[0], status='valid',
                      scope='printed exact guest function under default tiering; diagnostic execution, not performance')
    except BaseException as error:
        record['validation_error'] = repr(error)
        raise
    finally:
        save(directory / 'attempt.json', record)
    print('rng-code PASS full100; exact binary index; all printed code retained', flush=True)


# ---- Command entry ----


def main():
    global BUILD
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('verify', 'profile', 'gc', 'native-stats', 'rust-profile', 'counters', 'rng-code'))
    parser.add_argument('--build', type=Path, default=BUILD)
    options = parser.parse_args()
    BUILD = options.build.resolve()
    if options.action == 'verify':
        print(json.dumps(verify_inputs()))
    elif options.action == 'native-stats':
        run_native_stats()
    elif options.action == 'rust-profile':
        run_rust_profile()
    elif options.action == 'counters':
        run_counters()
    elif options.action == 'rng-code':
        run_rng_code()
    else:
        run_host(options.action)


if __name__ == '__main__':
    main()
