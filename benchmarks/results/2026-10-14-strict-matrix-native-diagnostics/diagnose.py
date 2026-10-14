#!/usr/bin/env python3
"""Inspect the frozen Matrix executors without changing their guest or GC policy."""

import argparse
from collections import defaultdict
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import time


# ---- Frozen inputs and diagnostic scope ----

ROOT = Path(__file__).resolve().parents[3]
BUILD = ROOT / 'build/matrix-native-diagnostics'
OWNER = Path('/tmp/snail-strict-matrix-20261014')
PREPARATION = OWNER / 'benchmarks/results/2026-10-14-strict-matrix-preparation'
CASE = OWNER / 'build/matrix-attempt5/matrix'
PLAN = PREPARATION / 'timing-plan.json'
PLAN_SHA = '27ad980f6dfbae3702fd5dd20f7eda357eb3fc849a34161e80f4001ddaccddec'
PERF = Path('/nix/store/apffmxq24i2xf89m4llsz4yc2sc1bv94-perf-linux-7.2.3/bin/perf')
COUNTER_BUILD = BUILD / 'counter-sources-03'
COUNTER_RUN = BUILD / 'native-counters-03'
SNAPSHOT_ROOT = None
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


def audited_path(path):
    if SNAPSHOT_ROOT is not None and str(path).startswith(str(OWNER) + '/'):
        return SNAPSHOT_ROOT / str(path).lstrip('/')
    return Path(path)


def verify_inputs():
    plan = load(PLAN)
    for path, expected in plan['identities'].items():
        require(identity(audited_path(path))['sha256'] == expected, 'clean identity changed: ' + path)
    require(plan['cpu'] in os.sched_getaffinity(0), 'requested CPU unavailable')
    return dict(plan=identity(PLAN), clean_identities=len(plan['identities']), unchanged=True)


def audit_inputs():
    audit = dict(started_utc=datetime.now(timezone.utc).isoformat(), files={}, errors=[])
    try:
        expected = {str(PLAN): PLAN_SHA, **load(PLAN)['identities']}
        for path, sha in expected.items():
            actual = identity(audited_path(path))['sha256']
            audit['files'][path] = dict(expected=sha, observed=actual)
            if actual != sha:
                audit['errors'].append('identity changed: ' + path)
        require(load(PLAN)['cpu'] in os.sched_getaffinity(0), 'requested CPU unavailable')
    except BaseException as error:
        audit['errors'].append(repr(error))
    audit.update(unchanged=not audit['errors'], stopped_utc=datetime.now(timezone.utc).isoformat())
    return audit


def freeze():
    BUILD.mkdir(exist_ok=False, parents=True)
    files = [PLAN, PREPARATION / 'timing-plan.md', PREPARATION / 'measure-seven.py',
             OWNER / 'build/matrix-seven-system-campaign-20261014/campaign.json',
             *[Path(path) for path in load(PLAN)['identities'] if path.startswith(str(OWNER) + '/')]]
    for path in dict.fromkeys(files):
        target = BUILD / 'inputs' / str(path).lstrip('/')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    save(BUILD / 'input-manifest.json', dict(verified=verify_inputs(),
         files=[identity(path) for path in dict.fromkeys(files)],
         argv_cwd_inputs='original frozen paths; copied bytes retained for audit',
         clean_timing=False))


# ---- Additions erase exactly to the measured V8 host ----

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


def profile_host():
    original_path = Path(load(PLAN)['systems']['strict-v8-native-final']['argv'][1])
    original = original_path.read_text()
    changes = [('import fs', PROFILE_HEADER + 'import fs'),
               ('const start = process.hrtime.bigint();', PROFILE_START + 'const start = process.hrtime.bigint();'),
               ('const seconds = Number(process.hrtime.bigint() - start) / 1e9;', PROFILE_STOP)]
    return write_derived(original_path, BUILD / 'profile-host.mjs', changes)


def write_derived(original_path, target, changes):
    proof_path = target.with_suffix(target.suffix + '.proof.json')
    proof = dict(status='preparing', original_path=str(original_path), derived_path=str(target), changes=changes)
    save(proof_path, proof)
    try:
        original = original_path.read_text()
        derived = replace_unique(original, changes)
        require(replace_unique(derived, [(after, before) for before, after in reversed(changes)]).encode() ==
                original_path.read_bytes(), 'additions failed exact byte erasure')
        target.write_text(derived)
        proof.update(status='valid', original=identity(original_path), derived=identity(target), exact_byte_erasure=True)
    except BaseException as error:
        proof.update(status='failed', error=repr(error))
        raise
    finally:
        save(proof_path, proof)
    return target


def replace_unique(original, changes):
    derived = original
    for before, after in changes:
        require(derived.count(before) == 1, 'source replacement is not unique')
        derived = derived.replace(before, after)
    return derived


# ---- A bounded process owns its regular capture files and all group members ----


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


def reap_group(child):
    before = group_members(child.pid)
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    child.wait(timeout=10)
    deadline = time.monotonic() + 10
    after = group_members(child.pid)
    while any(member['state'] not in ('Z', 'X') for member in after):
        require(time.monotonic() < deadline, 'executing owned descendants remain')
        time.sleep(0.01)
        after = group_members(child.pid)
    return dict(before=before, after=after, live_members=[], leader_reaped=True,
                zombies_dead_not_running=True)


def wait_bounded(child, directory, deadline):
    while child.poll() is None:
        if time.monotonic() >= deadline:
            return 'timeout'
        if any((directory / name).stat().st_size > 16 * 1024 * 1024 for name in ('stdout.bin', 'stderr.bin')):
            return 'capture-limit'
        time.sleep(0.02)
    return 'exited'


def execute(command, directory, cwd, environment=None):
    # This transaction keeps launch, capture, persistence and cleanup together.
    directory.mkdir(exist_ok=False)
    env = {k: v for k, v in os.environ.items() if k not in REMOVED}
    env.update(BINARYEN_CORES='1', **(environment or {}))
    record = dict(command=list(map(str, command)), cwd=str(cwd), status='started', clean_timing=False,
                  started_utc=datetime.now(timezone.utc).isoformat(), timeout_seconds=60,
                  driver=identity(Path(__file__)), errors=[],
                  environment={name: env.get(name) for name in (*REMOVED, 'BINARYEN_CORES', 'LD_LIBRARY_PATH', 'LANG', 'LC_ALL', 'TZ')})
    path, child, started = directory / 'attempt.json', None, time.monotonic()
    for name in ('stdout.bin', 'stderr.bin'):
        (directory / name).write_bytes(b'')
    save(path, record)
    try:
        record['identities_before'] = audit_inputs()
        require(record['identities_before']['unchanged'], 'pre-run identity audit failed')
        with (directory / 'stdout.bin').open('wb') as out, (directory / 'stderr.bin').open('wb') as err:
            child = subprocess.Popen(record['command'], cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                     stdout=out, stderr=err, start_new_session=True)
            record.update(pid=child.pid, process_group=child.pid, status='running')
            save(path, record)
            record['status'] = wait_bounded(child, directory, started + 60)
    except BaseException as error:
        record.update(status='failed')
        record['errors'].append(repr(error))
    finally:
        if child is not None:
            try:
                record['cleanup'] = reap_group(child)
                record['returncode'] = child.returncode
            except BaseException as error:
                record['errors'].append('cleanup: ' + repr(error))
        record.update(diagnostic_process_seconds=time.monotonic() - started,
                      stdout_raw=identity(directory / 'stdout.bin'), stderr_raw=identity(directory / 'stderr.bin'),
                      identities_after=audit_inputs())
        if not record['identities_after']['unchanged']:
            record['errors'].append('post-run identity audit failed')
        if record['errors']:
            record['status'] = 'failed'
        save(path, record)
    return record


# ---- Full result validation precedes diagnostic interpretation ----


def validate_result(record, directory, native, stdout=None):
    require(record['status'] == 'exited' and record['returncode'] == 0, 'process failed or exceeded its bound')
    require(record.get('cleanup', {}).get('live_members') == [], 'process group cleanup failed')
    require(record['identities_before']['unchanged'] and record['identities_after']['unchanged'], 'input identities changed')
    require(load(PLAN)['systems']['strict-native']['argv'][1] == '2500' and
            load(CASE / 'spec.json')['count'] == 2500, 'frozen invocation count differs')
    stdout = (directory / 'stdout.bin').read_text() if stdout is None else stdout
    require(stdout.endswith('\n') and len(stdout.splitlines()) == 1, 'unexpected stdout framing')
    result = json.loads(stdout)
    expected = dict(result=1, barriers=0) if native else dict(result='1', barriers=None, setup_barriers=None)
    require(set(result) == set(expected) | {'seconds'}, 'unexpected result fields')
    require(all(type(result[k]) is type(v) and result[k] == v for k, v in expected.items()), 'full predicate or barriers differ')
    require(type(result['seconds']) in (int, float) and math.isfinite(result['seconds']) and result['seconds'] > 0, 'invalid diagnostic clock')
    record.update(valid_full_result=True, diagnostic_workload_seconds=result['seconds'], full_count=2500)


def summarize_profile(path):
    profile, weights, hits = load(path), defaultdict(int), defaultdict(int)
    nodes = {node['id']: node for node in profile['nodes']}
    require(len(nodes) == len(profile['nodes']) and nodes, 'duplicate/empty profile nodes')
    require(len(profile['samples']) == len(profile['timeDeltas']) > 0, 'samples/deltas differ or are empty')
    require(all(type(profile.get(k)) in (int, float) and math.isfinite(profile[k]) for k in ('startTime', 'endTime')),
            'invalid profile timestamps')
    require(profile['endTime'] >= profile['startTime'] and sum(profile['timeDeltas']) > 0, 'invalid profile span')
    for sample, delta in zip(profile['samples'], profile['timeDeltas']):
        require(type(sample) is int and type(delta) is int and delta >= 0 and sample in nodes, 'invalid sample/delta')
        frame = nodes[sample]['callFrame']
        key = tuple(frame[k] for k in ('functionName', 'url', 'scriptId', 'lineNumber', 'columnNumber'))
        weights[key] += delta
        hits[key] += 1
    rows = [dict(function=k[0], url=k[1], script=k[2], line=k[3], column=k[4], samples=hits[k],
                 weighted_interval_us=w) for k, w in weights.items()]
    return dict(samples=len(profile['samples']), weighted_interval_us=sum(profile['timeDeltas']),
                profile_span_us=profile['endTime'] - profile['startTime'],
                policy='exclusive leaf intervals merged by complete frame; boundary intervals retained whole; not continuous CPU execution',
                frames=sorted(rows, key=lambda row: row['weighted_interval_us'], reverse=True))


def run_v8_profile():
    plan, directory = load(PLAN), BUILD / 'v8-profile'
    system = plan['systems']['strict-v8-native-final']
    argv = [system['argv'][0], profile_host(), *system['argv'][2:], '--diagnostics', directory]
    command = [plan['taskset'], '-c', str(plan['cpu']), *argv]
    record = execute(command, directory, system['cwd'])
    try:
        validate_result(record, directory, native=False)
        require(not (directory / 'stderr.bin').read_bytes(), 'V8 guest wrote stderr')
        save(directory / 'summary.json', summarize_profile(directory / 'profile.cpuprofile'))
        record.update(status='valid', window=load(directory / 'profile-window.json'),
                      profile=identity(directory / 'profile.cpuprofile'))
    except BaseException as error:
        record['validation_error'] = repr(error)
        raise
    finally:
        save(directory / 'attempt.json', record)
    print('V8 profile valid, full2500, unchanged native-final guest; diagnostic only', flush=True)


def run_native(kind):
    plan, directory = load(PLAN), BUILD / kind
    system = plan['systems']['strict-native']
    environment = {'SNAIL_GC_STATS': '1'} if kind == 'native-stats' else {}
    prefix = [] if kind == 'native-stats' else [PERF, 'record', '-e', 'cycles:u', '-F', '999',
             '--call-graph', 'dwarf,16384', '-o', directory / 'perf.data', '--']
    if kind == 'native-perf-leaf':
        prefix = [PERF, 'record', '-e', 'cpu_core/cycles/u', '-c', '1000003', '-o', directory / 'perf.data', '--']
    command = [plan['taskset'], '-c', str(plan['cpu']), *prefix, *system['argv']]
    record = execute(command, directory, system['cwd'], environment)
    try:
        validate_result(record, directory, native=True)
        if kind == 'native-stats':
            stderr = (directory / 'stderr.bin').read_text()
            require(re.fullmatch(r'immix-gc .*\n', stderr) is not None, 'unexpected collector stats framing')
            fields = dict(item.split('=', 1) for item in stderr.strip().split()[1:])
            record['gc_statistics'] = {k: float(v) if k.endswith('_s') else int(v) if v.isdecimal() else v
                                       for k, v in fields.items()}
        record.update(status='valid', scope='whole process, including initialization and cleanup; not timer bracketed')
    except BaseException as error:
        record['validation_error'] = repr(error)
        raise
    finally:
        save(directory / 'attempt.json', record)
    print(kind, 'valid, full2500, unchanged native binary; diagnostic only', flush=True)


# ---- Explicit operations keep expensive runs separate ----


def uleb(data, position):
    value, shift = 0, 0
    while True:
        require(position < len(data) and shift < 35, 'invalid binary ULEB32')
        byte, position = data[position], position + 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, position
        shift += 7


def name_string(data, position):
    length, position = uleb(data, position)
    require(position + length <= len(data), 'truncated binary name')
    return data[position:position + length].decode(), position + length


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


def save_function_map():
    module = Path(load(PLAN)['systems']['strict-v8-native-final']['argv'][2])
    names = function_names(module.read_bytes())
    save(BUILD / 'function-map.json', dict(module=identity(module), names=names,
         native_symbol='f.N uses binary index N, including imports; profile function names are retained Wasm names'))
    return names


# ---- Reversible counters record lowering requests, never clean elapsed time ----

COUNTER_DECLARATIONS = '''declare void @matrix_diag_count(i64)
declare void @matrix_diag_add(i64, i64)
declare void @matrix_diag_function(i64)
declare void @matrix_diag_type(i64)
'''
COUNTER_PROTOTYPES = '''void matrix_diag_count(uint64_t);
void matrix_diag_add(uint64_t, uint64_t);
void matrix_diag_type(uint64_t);
void matrix_diag_allocation(uint64_t);
'''


def counted_llvm(original_path, target):
    original, lines, root_slots, allocations, pointers, headers = original_path.read_text(), [], {}, set(), {}, {}
    additions, function = [], None
    for number, line in enumerate(original.splitlines(keepends=True)):
        match = re.match(r'define internal tailcc .* @f\.(\d+)\(', line)
        if match:
            function, root_slots, allocations, pointers, headers = int(match[1]), {}, set(), {}, {}
        before, after = llvm_counter_additions(line, root_slots, allocations, pointers, headers)
        if line == 'entry:\n' and function is not None:
            after += f'  call void @matrix_diag_function(i64 {function})\n'
        lines.extend([before, line, after])
        if before or after:
            additions.append(dict(line=number + 1, before=before, after=after))
        if line == '}\n':
            function = None
    derived = ''.join(lines) + COUNTER_DECLARATIONS
    erased = ''.join(line for line in derived.splitlines(keepends=True) if '@matrix_diag_' not in line)
    require(erased.encode() == original_path.read_bytes(), 'LLVM counters failed exact erasure')
    target.write_text(derived)
    save(target.with_suffix('.proof.json'), dict(original=identity(original_path), derived=identity(target),
         exact_byte_erasure=True, additions=additions, scope='logical requests; added calls can inhibit LLVM optimization'))


def llvm_counter_additions(line, root_slots, allocations, pointers, headers):
    before, after = '', ''
    slot = re.match(r'  (%\w+) = getelementptr i64, ptr %roots, i64 (\d+)\n', line)
    if slot:
        root_slots[slot[1]] = int(slot[2])
    allocation = re.match(r'  (%\w+) = call i64 @native_alloc\(', line)
    if allocation:
        allocations.add(allocation[1])
    pointer = re.match(r'  (%\w+) = inttoptr i64 (%\w+) to ptr\n', line)
    if pointer and pointer[2] in allocations:
        pointers[pointer[1]] = pointer[2]
    header = re.match(r'  (%\w+) = getelementptr i64, ptr (%\w+), i64 (\d+)\n', line)
    if header and header[2] in pointers:
        headers[header[1]] = int(header[3])
    store = re.match(r'  store (i32|i64|double|ptr) ([^,]+), ptr (%\w+), align 1\n', line)
    if store and store[3] in root_slots:
        after += f'  call void @matrix_diag_count(i64 {18 if root_slots[store[3]] == 2 else 17})\n'
    if store and store[3] in headers:
        if headers[store[3]] == 0 and store[1] == 'i64' and store[2].isdecimal():
            after += f'  call void @matrix_diag_type(i64 {store[2]})\n'
        elif headers[store[3]] > 0:
            after += f'  call void @matrix_diag_count(i64 22)\n  call void @matrix_diag_add(i64 23, i64 {4 if store[1] == "i32" else 8})\n'
    if re.search(r'\bcall tailcc .* @f\.\d+\(', line):
        before += '  call void @matrix_diag_count(i64 19)\n'
    if re.search(r'\bcall tailcc .* %\w+\(', line):
        before += '  call void @matrix_diag_count(i64 20)\n'
    if re.search(r'  br i1 .* label %ok\d+, label %trap\d+\n', line):
        before += '  call void @matrix_diag_count(i64 21)\n'
    return before, after


def counter_sources():
    directory = COUNTER_BUILD
    directory.mkdir(exist_ok=False)
    origin = CASE / 'native-timing/native.native-r2n6qggl/module.ll'
    counted_llvm(origin, directory / 'module.ll')
    gc_changes = [('#include "precise-gc.h"\n', '#include "precise-gc.h"\n' + COUNTER_PROTOTYPES)]
    for anchor, addition in [
        ('void *native_gc_alloc(size_t bytes) {\n', '    matrix_diag_allocation(bytes);\n'),
        ('static uint64_t *allocate_header(size_t bytes) {\n',
         '    if (bytes <= BLOCK_SIZE && cursor && (size_t)(limit - cursor) >= bytes) matrix_diag_count(3);\n'),
        ('static bool acquire_hole(size_t bytes) {\n', '    matrix_diag_count(4);\n'),
        ('static uint64_t *allocate_large(size_t bytes) {\n', '    matrix_diag_count(5);\n'),
        ('void native_gc_collect(void) {\n', '    matrix_diag_count(6);\n')]:
        gc_changes.append((anchor, anchor + addition))
    gc_changes.extend([
        ('    record_start(header);\n', '    record_start(header);\n    matrix_diag_count(24);\n'),
        ('    *header = ((uint64_t)bytes << 2) | ALLOCATED;\n',
         '    *header = ((uint64_t)bytes << 2) | ALLOCATED;\n    matrix_diag_count(25);\n'),
        ('    memset(header + 1, 0, bytes);\n',
         '    memset(header + 1, 0, bytes);\n    matrix_diag_add(26, bytes); matrix_diag_count(27);\n')])
    write_derived(OWNER / 'src/precise-gc.c', directory / 'precise-gc.c', gc_changes)
    runtime_changes = [('#include "precise-gc.h"\n', '#include "precise-gc.h"\n' + COUNTER_PROTOTYPES)]
    for anchor, addition in [
        ('void native_roots_enter(NativeRoots *frame, uint64_t capacity) {\n',
         '    matrix_diag_count(7); matrix_diag_add(9, capacity); if (capacity) matrix_diag_count(8);\n'),
        ('void native_roots_leave(NativeRoots *frame) {\n', '    matrix_diag_count(10);\n'),
        ('uint32_t native_ref_test(uint64_t reference, int64_t type, uint32_t nullable, uint32_t exact) {\n',
         '    matrix_diag_count(11);\n'),
        ('uint64_t native_array_new(uint64_t type, uint32_t length, uint64_t initial) {\n',
         '    matrix_diag_count(12); matrix_diag_add(13, length); matrix_diag_type(type);\n'
         '    matrix_diag_add(28, (uint64_t)length + 2); matrix_diag_add(29, 16 + (uint64_t)length * 8);\n'),
        ('void *native_array_slot(uint64_t reference, uint32_t index) {\n', '    matrix_diag_count(14);\n'),
        ('                       uint32_t from, uint32_t count) {\n',
         '    matrix_diag_count(15); matrix_diag_add(16, count);\n')]:
        runtime_changes.append((anchor, anchor + addition))
    write_derived(OWNER / 'src/native.c', directory / 'native.c', runtime_changes)
    entry_changes = [('#include "native-provider.h"\n', '#include "native-provider.h"\nvoid matrix_diag_reset(void);\nvoid matrix_diag_report(void);\n'),
                     ('    assert(clock_gettime(CLOCK_MONOTONIC, &before) == 0);\n',
                      '    matrix_diag_reset();\n    assert(clock_gettime(CLOCK_MONOTONIC, &before) == 0);\n'),
                     ('    assert(clock_gettime(CLOCK_MONOTONIC, &after) == 0);\n',
                      '    assert(clock_gettime(CLOCK_MONOTONIC, &after) == 0);\n    matrix_diag_report();\n')]
    write_derived(CASE / 'native-timing/native-entry.c', directory / 'native-entry.c', entry_changes)
    return directory


def build_counters():
    directory = counter_sources()
    original = load(CASE / 'native-timing/native.native-r2n6qggl/build.json')['commands'][-1]['command']
    replacements = {str(CASE / 'native-timing/native.native-r2n6qggl/module.ll'): directory / 'module.ll',
                    str(OWNER / 'src/native.c'): directory / 'native.c',
                    str(OWNER / 'src/precise-gc.c'): directory / 'precise-gc.c',
                    str(CASE / 'native-timing/native-entry.c'): directory / 'native-entry.c',
                    str(OWNER / 'build/native-runtime/release/libsnail_runtime.a'):
                    OWNER / 'build/matrix-native-final-control-20261014/libsnail_runtime.a'}
    command = [replacements.get(value, value) for value in original]
    command[-1] = directory / 'native-counter'
    command[1:1] = ['-I', CASE / 'native-timing', Path(__file__).with_name('counters.c')]
    record = execute(command, BUILD / 'counter-build-03', ROOT)
    require(record['returncode'] == 0 and record['status'] == 'exited', 'counter build failed')
    save(directory / 'build-inputs.json', dict(original_command=original, replacements={k: str(v) for k, v in replacements.items()},
         added_counter_source=identity(Path(__file__).with_name('counters.c')), binary=identity(directory / 'native-counter'),
         production_module_unchanged=True, gc_policy_unchanged=True, timing_claims=False))


def run_counters():
    plan, directory = load(PLAN), COUNTER_RUN
    system = plan['systems']['strict-native']
    command = [plan['taskset'], '-c', str(plan['cpu']), COUNTER_BUILD / 'native-counter', *system['argv'][1:]]
    record = execute(command, directory, system['cwd'],
                     {'SNAIL_MATRIX_DIAGNOSTICS': str(directory / 'counts.json'), 'SNAIL_GC_STATS': '1'})
    try:
        validate_result(record, directory, native=True)
        counts = load(directory / 'counts.json')
        for scope in counts.values():
            require(sum(scope['sizes'].values()) == scope['operations']['allocation_requests'], 'size counts differ')
            require(sum(scope['types'].values()) == scope['operations']['allocation_requests'], 'type counts differ')
        record.update(status='valid', counter_output=identity(directory / 'counts.json'),
                      scope='setup ends immediately before original workload timer; worker ends after timer stop, before diagnostics I/O',
                      timing_claims=False, source_changes='derived LLVM/C insertion ledger; logical requests can inhibit optimization')
    except BaseException as error:
        record['validation_error'] = repr(error)
        raise
    finally:
        save(directory / 'attempt.json', record)
    print('Native counters valid, full2500; unchanged guest erases from derived LLVM; diagnostic only', flush=True)


def run_v8_code(name):
    plan, names = load(PLAN), save_function_map()
    selected = [index for index, value in names.items() if value == name]
    require(len(selected) == 1, 'name must select one binary function index')
    system, directory = plan['systems']['strict-v8-native-final'], BUILD / ('v8-code-' + name)
    command = [plan['taskset'], '-c', str(plan['cpu']), system['argv'][0],
               '--print-wasm-code-function-index=' + str(selected[0]), *system['argv'][1:]]
    record = execute(command, directory, system['cwd'])
    record.update(scope='whole process; printed machine code, not timing', selected_name=name, selected_index=selected[0])
    text = (directory / 'stdout.bin').read_text()
    rows = [line for line in text.splitlines() if line.startswith('{"seconds":')]
    require(len(rows) == 1 and name in text and record['returncode'] == 0, 'missing code or full result')
    validate_result(record, directory, native=False, stdout=rows[0] + '\n')
    save(directory / 'attempt.json', record)


def inspect_native():
    binary = load(PLAN)['systems']['strict-native']['argv'][0]
    data = BUILD / 'native-perf/perf.data'
    commands = {
        'perf-header': [PERF, 'report', '-i', data, '--header-only', '--stdio'],
        'perf-events': [PERF, 'evlist', '-i', data, '-v'],
        'perf-report': [PERF, 'report', '-i', data, '--stdio', '--no-children', '--percent-limit', '0', '-n', '--sort', 'dso,symbol'],
        'perf-script-no-cpu': [PERF, 'script', '-i', data, '--ns', '-F', 'comm,pid,tid,time,event,ip,sym,dso,period'],
        'native-symbols': ['llvm-nm', '--numeric-sort', '--print-size', binary],
        'native-disassembly': ['llvm-objdump', '--disassemble', '--no-show-raw-insn', binary],
        'perf-annotate-alloc': [PERF, 'annotate', '-i', data, '--stdio', '--symbol', 'native_gc_alloc'],
        'perf-annotate-header': [PERF, 'annotate', '-i', data, '--stdio', '--symbol', 'allocate_header'],
        'perf-annotate-f33': [PERF, 'annotate', '-i', data, '--stdio', '--symbol', 'f.33'],
        'perf-annotate-gc': [PERF, 'annotate', '-i', data, '--stdio', '--symbol', 'native_gc_collect'],
        'perf-leaf-header': [PERF, 'report', '-i', BUILD / 'native-perf-leaf/perf.data', '--header-only', '--stdio'],
        'perf-leaf-report': [PERF, 'report', '-i', BUILD / 'native-perf-leaf/perf.data', '--stdio', '--no-children', '--percent-limit', '0', '-n', '--sort', 'dso,symbol'],
    }
    for name, command in commands.items():
        if (BUILD / name).exists():
            print(name, 'existing attempt preserved', flush=True)
            continue
        record = execute(command, BUILD / name, BUILD)
        require(record['status'] == 'exited' and record['returncode'] == 0, name + ' failed')
        print(name, 'captured', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('freeze', 'v8-profile', 'native-stats', 'native-perf', 'native-perf-leaf', 'inspect-native', 'function-map', 'v8-code', 'build-counters', 'native-counters'))
    parser.add_argument('--function', default='function88')
    arguments = parser.parse_args()
    if arguments.operation == 'freeze':
        freeze()
    elif arguments.operation == 'v8-profile':
        run_v8_profile()
    elif arguments.operation == 'inspect-native':
        inspect_native()
    elif arguments.operation == 'function-map':
        save_function_map()
    elif arguments.operation == 'v8-code':
        run_v8_code(arguments.function)
    elif arguments.operation == 'build-counters':
        build_counters()
    elif arguments.operation == 'native-counters':
        run_counters()
    else:
        run_native(arguments.operation)


if __name__ == '__main__':
    main()
