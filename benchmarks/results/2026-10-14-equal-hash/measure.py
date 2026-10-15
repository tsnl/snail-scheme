#!/usr/bin/env python3
"""Verify the frozen Equal experiment, or execute it after coordinated release."""

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import signal
import statistics
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
REPORT = Path(__file__).resolve().parent
MODES = ('production-v8', 'native-final-v8', 'native64')
SYSTEMS = tuple(revision + '-' + mode for mode in MODES for revision in ('baseline', 'candidate'))
REJECTED_ENVIRONMENT = ('NODE_OPTIONS', 'NODE_V8_COVERAGE', 'NODE_DEBUG', 'NODE_DEBUG_NATIVE',
    'LD_PRELOAD', 'SNAIL_NATIVE_GC_INTERVAL', 'SNAIL_GC_STATS', 'SNAIL_GC_HEAP_BYTES',
    'SNAIL_GC_MIN_BYTES', 'SNAIL_INTEGER_TIME', 'CHEZSCHEMELIBDIRS', 'SCHEMEHEAPDIRS')
RECORDED_ENVIRONMENT = (*REJECTED_ENVIRONMENT, 'LD_LIBRARY_PATH', 'LANG', 'LC_ALL', 'TZ', 'PATH',
    'CHIBI', 'NODE', 'WASM_AS', 'WASM_OPT', 'WASM_DIS', 'WASM_MERGE', 'CLANG', 'LLD',
    'RUSTC', 'CARGO', 'PYTHON', 'TASKSET', 'CARGO_HOME', 'RUSTUP_HOME', 'CARGO_TARGET_DIR',
    'MALLOC_ARENA_MAX', 'MALLOC_PERTURB_', 'GLIBC_TUNABLES', 'UV_THREADPOOL_SIZE')
STOP_SIGNAL = None


# ---- Content identities and the predetermined six-system schedule ----

def save(path, value):
    temporary = path.with_name(path.name + '.pending')
    with temporary.open('w') as target:
        target.write(json.dumps(value, indent=2, allow_nan=False) + '\n')
        target.flush()
        os.fsync(target.fileno())
    temporary.replace(path)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def schedule():
    rows = [dict(system=system, phase='discarded-warmup', round=-1, position=index)
            for index, system in enumerate(SYSTEMS)]
    base = (0, 1, 5, 2, 4, 3)
    for round_number in range(12):
        order = base if round_number < 6 else tuple(reversed(base))
        rows += [dict(system=SYSTEMS[(value + round_number % 6) % 6],
                      phase='measurement', round=round_number, position=position)
                 for position, value in enumerate(order)]
    return [dict(index=index, **row) for index, row in enumerate(rows)]


def dependency_files():
    files = {Path(sys.executable).resolve()}
    for module in tuple(sys.modules.values()):
        for attribute in ('__file__', '__cached__'):
            path = getattr(module, attribute, None)
            if path and Path(path).is_file():
                files.add(Path(path).resolve())
    return sorted(map(str, files))


def verify_environment(plan):
    require(plan['cpu'] == 5 and 5 in os.sched_getaffinity(0), 'CPU 5 is unavailable')
    for name in REJECTED_ENVIRONMENT:
        require(name not in os.environ, 'execution environment must unset ' + name)
    actual = {name: os.environ.get(name) for name in RECORDED_ENVIRONMENT}
    require(actual == plan['inherited_environment'], 'inherited environment changed')
    require(plan['environment'] == {'BINARYEN_CORES': '1'}, 'explicit environment changed')


def verify_identities(plan, paths):
    for path in paths:
        require(plan['identities'].get(str(path)) == digest(path), 'identity changed: ' + str(path))


def verify(plan):
    verify_environment(plan)
    require(plan['schedule'] == schedule() and plan['systems'] == list(SYSTEMS), 'schedule changed')
    require(plan['rounds'] == 12 and plan['timeout_seconds'] == 60, 'sampling policy changed')
    require(plan['input_parameters'] == [100, 100, 8, 1000, 2000, 5000], 'full Equal input changed')
    require(plan['warmup_processes'] == 6 and plan['measured_processes'] == 72, 'sample counts changed')
    verify_identities(plan, plan['identities'])
    verify_identities(plan, dependency_files())


# ---- A process group remains owned until termination and byte capture finish ----

def request_stop(number, frame):
    global STOP_SIGNAL
    STOP_SIGNAL = number


def check_stop():
    if STOP_SIGNAL is not None:
        raise KeyboardInterrupt('received ' + signal.Signals(STOP_SIGNAL).name)


def group_members(group):
    members = []
    for path in Path('/proc').glob('[0-9]*/stat'):
        try:
            fields = path.read_text().rsplit(')', 1)[1].split()
            if int(fields[2]) == group and fields[0] not in ('Z', 'X'):
                members.append(int(path.parent.name))
        except (OSError, ValueError, IndexError):
            pass
    return sorted(members)


def clean_group(group):
    deadline = time.monotonic() + 5
    while True:
        try:
            os.killpg(group, signal.SIGKILL)
        except ProcessLookupError:
            pass
        remaining = group_members(group)
        if not remaining or time.monotonic() >= deadline:
            return remaining
        time.sleep(0.02)


def wait_for_leader(child, timeout):
    deadline = time.monotonic() + timeout
    while child.poll() is None:
        remaining = deadline - time.monotonic()
        if STOP_SIGNAL is not None or remaining <= 0:
            return dict(timeout=remaining <= 0, interrupted=STOP_SIGNAL is not None)
        try:
            child.wait(timeout=min(remaining, 0.05))
        except subprocess.TimeoutExpired:
            pass
    return dict(timeout=False, interrupted=STOP_SIGNAL is not None)


def record_terminal(child, record):
    record['returncode'] = child.returncode
    record['termination'] = (dict(exit_status=child.returncode, signal=None) if child.returncode >= 0
                             else dict(exit_status=None, signal=-child.returncode))


def finish_owned(child, record):
    # The leader's wait status is recorded separately from descendants. Killing
    # unexpected descendants cannot turn unfinished guest work into a success.
    record['executing_descendants'] = [pid for pid in group_members(child.pid) if pid != child.pid]
    remaining = clean_group(child.pid)
    record['cleanup'] = dict(process_group=child.pid, live_members=remaining,
        leader_reaped=False, zombies_count_as_stopped=True, policy='SIGKILL, bounded five seconds')
    child.wait(timeout=10)
    record_terminal(child, record)
    record['cleanup']['leader_reaped'] = True


def run_owned(config, environment, timeout, record, directory):
    started, child = time.perf_counter(), None
    try:
        with (directory/'stdout.bin').open('xb') as stdout, (directory/'stderr.bin').open('xb') as stderr:
            try:
                check_stop()
                child = subprocess.Popen(config['command'], cwd=config['cwd'], env=environment,
                    stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr, start_new_session=True)
                # Handlers only request a stop. Ownership is registered before
                # a stop can unwind this transition, including Popen's return.
                record.update(pid=child.pid, process_group=child.pid, status='running')
                save(directory/'record.json', record)
                record.update(wait_for_leader(child, timeout))
            finally:
                try:
                    if child is not None:
                        finish_owned(child, record)
                finally:
                    for capture in (stdout, stderr):
                        capture.flush()
                        os.fsync(capture.fileno())
    finally:
        record.update(capture_handles_closed=True, process_seconds=time.perf_counter() - started)


def capture_identities(directory, record):
    record['captures'] = {}
    for name in ('stdout', 'stderr'):
        path = directory/(name + '.bin')
        if path.exists():
            record['captures'][name] = dict(path=str(path), bytes=path.stat().st_size, sha256=digest(path))
    cleanup = record.get('cleanup', {})
    record['capture_complete'] = (record.get('capture_handles_closed', False)
                                 and cleanup.get('leader_reaped', False) and not cleanup.get('live_members', [1]))
    record['stop_signal'] = STOP_SIGNAL


# ---- Complete Equal JSON frames are parsed only after terminal evidence is saved ----

def distinct_fields(pairs):
    value = {}
    for name, item in pairs:
        require(name not in value, 'duplicate JSON field: ' + name)
        value[name] = item
    return value


def positive_seconds(value):
    require(type(value) in (int, float) and math.isfinite(value) and value > 0, 'invalid positive clock')
    return value


def frame_seconds(system, output):
    require(output.endswith(b'\n') and output.count(b'\n') == 1, 'complete JSON frame differs')
    value = json.loads(output.decode('utf-8'), object_pairs_hook=distinct_fields)
    expected = dict(result=1)
    if system.endswith('-native64'):
        expected.update(barriers=0, setup_closed=1, worker_closed=0, closed=1)
    require(type(value) is dict and set(value) == set(expected) | {'seconds'}, 'frame fields differ')
    require(all(type(value[key]) is int and value[key] == amount for key, amount in expected.items()),
            'complete predicate or native resource lifetime differs')
    return positive_seconds(value['seconds'])


def check_result(system, record, directory):
    require(record['returncode'] == 0 and record['termination'] == dict(exit_status=0, signal=None), 'guest exit differs')
    require(not record['timeout'] and not record['interrupted'] and record['stop_signal'] is None, 'timeout or interruption')
    require(record['capture_complete'] and record['capture_handles_closed'], 'capture incomplete')
    require(not record['executing_descendants'] and not record['cleanup']['live_members'], 'unexpected descendants')
    require(record['cleanup']['leader_reaped'], 'leader not reaped')
    require((directory/'stderr.bin').read_bytes() == b'', 'guest wrote stderr')
    positive_seconds(record['process_seconds'])
    return frame_seconds(system, (directory/'stdout.bin').read_bytes())


def sample(plan, row, directory):
    config = plan['configurations'][row['system']]
    verify_environment(plan)
    verify_identities(plan, config['dependencies'])
    directory.mkdir(exist_ok=False)
    record = dict(row, **config, started=datetime.now(timezone.utc).isoformat(), status='starting',
                  environment=plan['environment'], inherited_environment=plan['inherited_environment'],
                  diagnostic_only=False)
    save(directory/'record.json', record)
    try:
        run_owned(config, {**os.environ, **plan['environment']}, plan['timeout_seconds'], record, directory)
        capture_identities(directory, record)
        save(directory/'record.json', record)
        record.update(workload_seconds=check_result(row['system'], record, directory), status='valid')
    except BaseException as error:
        record.update(status='failed', error=repr(error))
        raise
    finally:
        capture_identities(directory, record)
        save(directory/'record.json', record)
    return record


# ---- All samples contribute to system medians and matched revision comparisons ----

def summarize(samples):
    systems, times = {}, {}
    for system in SYSTEMS:
        rows = [row for row in samples if row['system'] == system and row['phase'] == 'measurement']
        require(len(rows) == 12 and [row['round'] for row in rows] == list(range(12)), 'retained rounds differ')
        times[system] = [row['workload_seconds'] for row in rows]
        systems[system] = dict(samples=12, median=statistics.median(times[system]),
                              range=[min(times[system]), max(times[system])])
    return dict(systems=systems, comparisons=revision_comparisons(times, systems))


def revision_comparisons(times, systems):
    result = {}
    for mode in MODES:
        baseline, candidate = 'baseline-'+mode, 'candidate-'+mode
        paired = [b/a for a, b in zip(times[baseline], times[candidate])]
        ratio = systems[candidate]['median'] / systems[baseline]['median']
        result[mode] = dict(candidate_over_baseline=ratio, percent_less_time=100*(1-ratio),
                            paired_round_ratios=paired, paired_median=statistics.median(paired))
    return result


def host_snapshot(cpu):
    prefix = Path(f'/sys/devices/system/cpu/cpu{cpu}')
    files = [prefix/'cpufreq'/name for name in ('scaling_driver', 'scaling_governor',
        'scaling_min_freq', 'scaling_max_freq', 'scaling_cur_freq', 'affected_cpus')]
    files += [prefix/'topology/thread_siblings_list', Path('/sys/devices/system/cpu/online'),
              Path('/sys/devices/system/cpu/intel_pstate/no_turbo'), Path('/sys/devices/system/cpu/cpufreq/boost')]
    blocks = Path('/proc/cpuinfo').read_text().split('\n\n')
    info = next(block for block in blocks if re.search(rf'^processor\s*:\s*{cpu}$', block, re.M))
    return dict(date=datetime.now(timezone.utc).isoformat(), cpu=cpu, affinity=sorted(os.sched_getaffinity(0)),
        platform=platform.uname()._asdict(), cpuinfo=info, loadavg=os.getloadavg(),
        policy={str(path): path.read_text().strip() if path.exists() else None for path in files})


def run_rows(plan, output, report):
    for row in plan['schedule']:
        check_stop()
        report['pending_sample'] = row
        save(output/'campaign.json', report)
        record = sample(plan, row, output/f'sample-{row["index"]:03}')
        report['samples'].append(record)
        save(output/'campaign.json', report)
        print(row['index'], row['system'], row['phase'], 'verified', flush=True)


def execute(plan, output, release):
    verify(plan)
    output.mkdir(parents=True, exist_ok=False)
    report = dict(plan_sha256=digest(REPORT/'timing-plan.json'), complete=False,
                  diagnostic_only=False, coordinated_release=release, samples=[])
    save(output/'host-before.json', host_snapshot(plan['cpu']))
    try:
        run_rows(plan, output, report)
        verify(plan)
        report.update(summary=summarize(report['samples']), complete=True)
        report.pop('pending_sample')
    except BaseException as error:
        report['error'] = repr(error)
        raise
    finally:
        save(output/'host-after.json', host_snapshot(plan['cpu']))
        save(output/'campaign.json', report)


def options():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group()
    actions.add_argument('--run', action='store_true')
    actions.add_argument('--dependency-files', action='store_true')
    actions.add_argument('--self-test', action='store_true')
    parser.add_argument('--expected-plan-sha256')
    parser.add_argument('--coordinated-release', help='record the root quiet-window release')
    parser.add_argument('--output', type=Path)
    return parser, parser.parse_args()


def main():
    parser, arguments = options()
    if arguments.dependency_files:
        print(json.dumps(dependency_files()))
        return
    if arguments.self_test:
        self_test()
        return
    plan_path = REPORT/'timing-plan.json'
    plan = json.loads(plan_path.read_text())
    if not arguments.run:
        verify(plan)
        print('PASS frozen schedule, sources, artifacts and import closure; no guest started')
        return
    if not arguments.output or not arguments.coordinated_release or not arguments.expected_plan_sha256:
        parser.error('--run requires fresh --output, --expected-plan-sha256 and --coordinated-release')
    require(digest(plan_path) == arguments.expected_plan_sha256, 'plan hash differs')
    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)
    execute(plan, arguments.output, arguments.coordinated_release)


# ---- Tests ----

def test_frames():
    frame = b'{"result":1,"seconds":0.25}\n'
    require(frame_seconds('baseline-production-v8', frame) == 0.25, 'valid frame rejected')
    rejected = [frame+b'\n', frame.replace(b'1,', b'true,'), frame.replace(b'1,', b'1.0,'),
        frame.replace(b'0.25', b'0'), frame.replace(b'0.25', b'NaN'), frame.replace(b'0.25', b'true'),
        frame.replace(b'"result":1', b'"result":1,"result":1'), frame[:-1], b'\xff\n',
        frame.replace(b'"result":1', b'"result":1,"extra":0')]
    for broken in rejected:
        try:
            frame_seconds('baseline-production-v8', broken)
        except (ValueError, UnicodeError):
            continue
        raise AssertionError('corrupt full frame accepted: ' + repr(broken))


def test_balance():
    rows = [row for row in schedule() if row['phase'] == 'measurement']
    orders = [[SYSTEMS.index(row['system']) for row in rows if row['round'] == number] for number in range(12)]
    require(all(Counter(order[position] for order in orders) == Counter({i: 2 for i in range(6)})
                for position in range(6)), 'position balance differs')
    require(Counter((order[i], order[i+1]) for order in orders for i in range(5)) ==
            Counter({(a, b): 2 for a in range(6) for b in range(6) if a != b}), 'adjacency balance differs')
    require(all(sum(order.index(i) < order.index(i+1) for order in orders) == 6 for i in (0, 2, 4)), 'revision order differs')


def fixture(directory, source, timeout):
    directory.mkdir()
    config = dict(command=[sys.executable, '-c', source], cwd=str(directory))
    record = dict(status='starting')
    run_owned(config, dict(os.environ), timeout, record, directory)
    capture_identities(directory, record)
    save(directory/'record.json', record)
    require(record['capture_complete'] and record['cleanup']['leader_reaped'], 'fixture cleanup incomplete')
    return record


def test_processes(directory):
    source = 'import os; os.write(1,b"\\xff\\r\\n"); os.write(2,b"\\x80\\n"); raise SystemExit(7)'
    failed = fixture(directory/'nonzero', source, 2)
    require(failed['returncode'] == 7 and (directory/'nonzero/stdout.bin').read_bytes() == b'\xff\r\n', 'raw bytes lost')
    require((directory/'nonzero/stderr.bin').read_bytes() == b'\x80\n', 'stderr bytes lost')
    source = 'import os,time; os.write(1,b"partial\\n"); time.sleep(20)'
    expired = fixture(directory/'timeout', source, 0.1)
    require(expired['timeout'] and expired['returncode'] == -signal.SIGKILL, 'actual timeout termination differs')
    require((directory/'timeout/stdout.bin').read_bytes() == b'partial\n', 'timeout partial bytes lost')
    source = 'import os,time; pid=os.fork(); time.sleep(20) if pid==0 else None'
    orphan = fixture(directory/'descendant', source, 2)
    require(orphan['returncode'] == 0 and orphan['executing_descendants'], 'unexpected descendant not recorded')
    require(not orphan['cleanup']['live_members'], 'descendant survived cleanup')


def test_interruption(directory):
    global STOP_SIGNAL
    previous = signal.signal(signal.SIGTERM, request_stop)
    try:
        source = 'import os,signal,time; os.write(1,b"partial\\n"); os.kill(os.getppid(),signal.SIGTERM); time.sleep(20)'
        record = fixture(directory/'interrupted', source, 2)
        require(record['interrupted'] and record['stop_signal'] == signal.SIGTERM, 'stop request lost')
        require(record['returncode'] == -signal.SIGKILL and record['capture_complete'], 'interruption cleanup incomplete')
    finally:
        STOP_SIGNAL = None
        signal.signal(signal.SIGTERM, previous)


def self_test():
    test_frames()
    test_balance()
    with tempfile.TemporaryDirectory(prefix='equal-capture-tests-') as temporary:
        test_processes(Path(temporary))
        test_interruption(Path(temporary))
    print('PASS complete frames, schedule balance, raw byte capture, nonzero exit, timeout, descendants and SIGTERM')


if __name__ == '__main__':
    main()
