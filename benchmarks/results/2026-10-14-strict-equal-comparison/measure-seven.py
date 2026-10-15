#!/usr/bin/env python3
"""Run the frozen Equal schedule after the coordinated quiet-window release."""

import argparse
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
import time

sys.dont_write_bytecode = True


# ---- Frozen programs, imported supervision and inherited settings ----

REJECTED_ENVIRONMENT = ('NODE_OPTIONS', 'NODE_V8_COVERAGE', 'NODE_DEBUG',
    'NODE_DEBUG_NATIVE', 'LD_PRELOAD', 'SNAIL_NATIVE_GC_INTERVAL',
    'SNAIL_GC_STATS', 'SNAIL_GC_HEAP_BYTES', 'SNAIL_GC_MIN_BYTES')
RECORDED_ENVIRONMENT = (*REJECTED_ENVIRONMENT, 'LD_LIBRARY_PATH', 'LANG', 'LC_ALL', 'TZ')
SYSTEMS = ('strict-v8', 'strict-v8-native-module', 'strict-native',
           'chez-original', 'chez-adapted', 'rust-wasm', 'rust-native')
STOP_REQUESTED = None


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def unique_object(fields):
    value = {}
    for name, item in fields:
        if name in value:
            raise ValueError('duplicate JSON field: ' + name)
        value[name] = item
    return value


def dependency_files():
    files = set()
    for module in list(sys.modules.values()):
        for attribute in ('__file__', '__cached__'):
            name = getattr(module, attribute, None)
            if name and Path(name).is_file():
                files.add(str(Path(name).resolve()))
    return sorted(files)


def supervisor(preparation):
    sys.path.insert(0, preparation)
    import matrix_port
    return matrix_port


def verify_environment(plan):
    if plan['cpu'] not in os.sched_getaffinity(0):
        raise ValueError('requested CPU is unavailable')
    for name in REJECTED_ENVIRONMENT:
        if name in os.environ:
            raise ValueError('timing environment must unset ' + name)
    if {name: os.environ.get(name) for name in RECORDED_ENVIRONMENT} != plan['inherited_environment']:
        raise ValueError('recorded inherited environment changed')


def verify_policy(plan):
    expected = [dict(system=system, round=round_number, retained=round_number >= 0)
                for round_number in range(-1, 7)
                for system in SYSTEMS[max(0, round_number):] + SYSTEMS[:max(0, round_number)]]
    if (type(plan['cpu']) is not int or type(plan['timeout_seconds']) is not int or plan['cpu'] != 5
            or plan['timeout_seconds'] != 120 or tuple(plan['systems']) != SYSTEMS):
        raise ValueError('required CPU, timeout or seven-system policy changed')
    if any(type(row['round']) is not int or type(row['retained']) is not bool for row in plan['schedule']):
        raise ValueError('schedule round and retained flag must have their explicit types')
    if plan['schedule'] != expected or plan['environment'] != {'BINARYEN_CORES': '1'}:
        raise ValueError('required 56-job balanced schedule or environment changed')
    if plan['input_parameters'] != [100, 100, 8, 1000, 2000, 5000] or plan['chez_workload_name'] != 'equal:100:100:8:1000:2000:5000':
        raise ValueError('complete canonical Equal workload changed')


def verify(plan):
    check_stop()
    verify_policy(plan)
    supervisor(plan['preparation'])
    for path in dependency_files():
        if plan['identities'].get(path) != digest(path):
            raise ValueError('unfrozen imported dependency: ' + path)
    for path, expected in plan['identities'].items():
        if digest(path) != expected:
            raise ValueError('frozen identity changed: ' + path)
    verify_environment(plan)


# ---- Complete result frames and finite workload durations ----

def json_seconds(system, text):
    value = json.loads(text, object_pairs_hook=unique_object)
    if text.count('\n') != 1 or not text.endswith('\n'):
        raise ValueError('unexpected JSON framing')
    if system.startswith('strict-v8'):
        expected = dict(result=1)
    else:
        expected = dict(result=1, barriers=0, setup_closed=1, worker_closed=0, closed=1)
    if set(value) != set(expected) | {'seconds'} or any(type(value[key]) is not int or value[key] != number
                                                     for key, number in expected.items()):
        raise ValueError('unexpected strict result or file lifecycle')
    return value['seconds']


def scheme_seconds(name, text):
    number = r'[0-9.eE+\-]+'
    pattern = (rf'Running {re.escape(name)}\nElapsed time: ({number}) seconds \(({number})\) for '
               rf'{re.escape(name)}\n\+!CSVLINE!\+chez,{re.escape(name)},({number})\n')
    match = re.fullmatch(pattern, text)
    if not match:
        raise ValueError('unexpected complete Chez result framing')
    durations = [float(match[index]) for index in (1, 2, 3)]
    if durations[0] != durations[2] or any(not math.isfinite(value) or value < 0 for value in durations):
        raise ValueError('invalid or inconsistent Chez durations')
    return float(match[3])


def rust_seconds(text):
    match = re.fullmatch(r'Result: #t\n\+!CSVLINE!\+rust-wasm,equal:1,([0-9.eE+\-]+)\n', text)
    if not match:
        raise ValueError('unexpected complete Rust result framing')
    return float(match[1])


def workload_seconds(plan, system, record):
    if record['returncode'] != 0 or record['stderr'] or record['timeout']:
        raise ValueError('process failed, timed out or wrote stderr')
    if system.startswith('strict-'):
        seconds = json_seconds(system, record['stdout'])
    elif system.startswith('chez-'):
        seconds = scheme_seconds(plan['chez_workload_name'], record['stdout'])
    else:
        seconds = rust_seconds(record['stdout'])
    positive_duration(seconds, 'workload')
    positive_duration(record['process_seconds'], 'process')
    return seconds


def positive_duration(seconds, kind):
    if isinstance(seconds, bool) or not isinstance(seconds, (int, float)) or not math.isfinite(seconds) or seconds <= 0:
        raise ValueError('invalid positive ' + kind + ' duration')


# ---- One owned process group per fresh invocation ----

def request_stop(signum, frame):
    global STOP_REQUESTED
    STOP_REQUESTED = signum


def check_stop():
    if STOP_REQUESTED is not None:
        raise InterruptedError('campaign stop requested by signal ' + str(STOP_REQUESTED))


def capture_process(child, stdin, timeout, started, owned):
    while True:
        check_stop()
        remaining = timeout - (time.perf_counter() - started)
        if remaining <= 0:
            owned.clean_group(child.pid)
            stdout, stderr = child.communicate(timeout=10)
            return dict(returncode=child.returncode, stdout=stdout, stderr=stderr, timeout=True)
        try:
            stdout, stderr = child.communicate(stdin, timeout=min(0.05, remaining))
            return dict(returncode=child.returncode, stdout=stdout, stderr=stderr, timeout=False)
        except subprocess.TimeoutExpired:
            stdin = None


def cleanup_process(child, record, owned):
    remaining = owned.clean_group(child.pid)
    child.wait(timeout=10)
    stdout, stderr = child.communicate(timeout=10)
    record.update(stdout=stdout, stderr=stderr, returncode=child.returncode)
    record['cleanup'] = dict(process_group=child.pid, live_members=remaining, leader_reaped=child.returncode is not None,
                            capture_handles_closed=all(handle.closed for handle in (child.stdin, child.stdout, child.stderr)),
                            zombies_count_as_stopped=True)
    if remaining or not record['cleanup']['capture_handles_closed']:
        raise RuntimeError('owned child cleanup incomplete: ' + str(record['cleanup']))


def run_owned_process(plan, config, record, path, owned):
    check_stop()
    environment = dict(os.environ, **plan['environment'])
    stdin = Path(config['stdin']).read_text() if config['stdin'] else None
    child, started = None, time.perf_counter()
    try:
        # Signals record a stop flag while Popen returns its actual owned handle.
        child = subprocess.Popen(record['command'], cwd=config['cwd'], env=environment,
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, text=True, start_new_session=True)
        record.update(pid=child.pid, process_group=child.pid, status='running')
        save(path, record)
        check_stop()
        record.update(capture_process(child, stdin, plan['timeout_seconds'], started, owned))
        check_stop()
    finally:
        if child is not None:
            cleanup_process(child, record, owned)
        record.setdefault('timeout', False)
        record['process_seconds'] = time.perf_counter() - started


def sample(plan, scheduled, path, owned):
    verify(plan)
    config = plan['systems'][scheduled['system']]
    record = dict(scheduled, command=[plan['taskset'], '-c', str(plan['cpu']), *config['argv']],
                  cwd=config['cwd'], status='starting', started=datetime.now(timezone.utc).isoformat())
    save(path, record)
    try:
        run_owned_process(plan, config, record, path, owned)
        record.update(workload_seconds=workload_seconds(plan, scheduled['system'], record), status='valid')
    except BaseException as error:
        record.update(status='failed', error=repr(error))
        raise
    finally:
        save(path, record)
    return record


# ---- Fixed serial rotation and separate host observations ----

def summarize(samples):
    result = {}
    for system in dict.fromkeys(row['system'] for row in samples):
        rows = [row for row in samples if row['system'] == system and row['retained']]
        work, process = [row['workload_seconds'] for row in rows], [row['process_seconds'] for row in rows]
        result[system] = dict(samples=len(rows), workload_median=statistics.median(work),
                             workload_range=[min(work), max(work)], process_median=statistics.median(process),
                             process_range=[min(process), max(process)])
    return result


def host_snapshot(cpu):
    prefix = Path(f'/sys/devices/system/cpu/cpu{cpu}')
    files = [prefix / 'cpufreq' / name for name in ('scaling_driver', 'scaling_governor', 'scaling_min_freq',
             'scaling_max_freq', 'scaling_cur_freq', 'cpuinfo_min_freq', 'cpuinfo_max_freq', 'affected_cpus')]
    files += [prefix / 'topology/thread_siblings_list', Path('/sys/devices/system/cpu/online'),
              Path('/sys/devices/system/cpu/intel_pstate/no_turbo'), Path('/sys/devices/system/cpu/cpufreq/boost')]
    info = next(block for block in Path('/proc/cpuinfo').read_text().split('\n\n')
                if re.search(rf'^processor\s*:\s*{cpu}$', block, re.M))
    return dict(date=datetime.now(timezone.utc).isoformat(), cpu=cpu, affinity=sorted(os.sched_getaffinity(0)),
                platform=platform.uname()._asdict(), cpuinfo=info, loadavg=os.getloadavg(),
                policy={str(path): path.read_text().strip() if path.exists() else None for path in files})


def collect_samples(plan, output, report):
    owned = supervisor(plan['preparation'])
    for index, scheduled in enumerate(plan['schedule']):
        report['pending_sample'] = dict(index=index, **scheduled)
        save(output / 'campaign.json', report)
        record = sample(plan, scheduled, output / f'sample-{index:02}.json', owned)
        report['samples'].append(record)
        save(output / 'campaign.json', report)
        print(index, scheduled['system'], record['workload_seconds'], flush=True)
    report.pop('pending_sample')


def campaign(plan, output):
    output.mkdir(parents=True, exist_ok=False)
    report = dict(plan=plan, complete=False, samples=[],
                  inherited_environment={name: os.environ.get(name) for name in RECORDED_ENVIRONMENT})
    save(output / 'campaign.json', report)
    try:
        verify(plan)
        save(output / 'host-before.json', host_snapshot(plan['cpu']))
        collect_samples(plan, output, report)
        verify(plan)
        report.update(complete=True, summary=summarize(report['samples']))
    except BaseException as error:
        report['error'] = repr(error)
        raise
    finally:
        save(output / 'host-after.json', host_snapshot(plan['cpu']))
        save(output / 'campaign.json', report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', type=Path, default=Path(__file__).with_name('timing-plan.json'))
    parser.add_argument('--dependency-files', type=Path, help='list the actual imported closure without running a workload')
    parser.add_argument('--check-records', type=Path, help='replay complete captured frames and reject corruptions')
    parser.add_argument('--check-supervision', type=Path, help='exercise owned interruption and timeout captures')
    parser.add_argument('--preparation', type=Path,
                        default=Path(__file__).resolve().parents[3] / 'build/equal-prepared-6fd5ca4/frozen')
    parser.add_argument('--run', action='store_true', help='requires the coordinated quiet-window release')
    parser.add_argument('--output', type=Path)
    options = parser.parse_args()
    if options.check_supervision:
        test_owned_interruption(options.check_supervision, supervisor(str(options.preparation)))
        return
    if options.dependency_files:
        supervisor(str(options.dependency_files))
        print(json.dumps(dependency_files()))
        return
    plan = json.loads(options.plan.read_text())
    if options.check_records:
        test_result_frames(plan, json.loads(options.check_records.read_text()))
        return
    if not options.run:
        verify(plan)
        print('Verified frozen identities; no benchmark process started')
        return
    if options.output is None:
        parser.error('--run requires a new --output directory')
    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    campaign(plan, options.output)


# ---- Tests ----

def rejected_frame(plan, system, record):
    try:
        workload_seconds(plan, system, record)
    except (ValueError, TypeError, KeyError):
        return
    raise AssertionError('accepted corrupted complete result frame: ' + system)


def test_result_frames(plan, records):
    rejected = 0
    for system, path in records.items():
        original = json.loads(Path(path).read_text())
        workload_seconds(plan, system, original)
        corruptions = [dict(original, stdout=original['stdout'] + '\n'), dict(original, stderr='unexpected\n'),
                       dict(original, returncode=1), dict(original, timeout=True)]
        corruptions.extend(dict(original, process_seconds=bad) for bad in (False, 0, -1, float('nan'), float('inf')))
        if system.startswith('strict-'):
            value = json.loads(original['stdout'])
            corruptions.extend(dict(original, stdout=json.dumps(dict(value, seconds=bad)) + '\n')
                               for bad in (True, 0, -1, float('nan'), float('inf'), '1'))
            corruptions.extend(dict(original, stdout=json.dumps(dict(value, result=bad)) + '\n') for bad in (False, True, 0))
            corruptions.append(dict(original, stdout='{"result":1,' + json.dumps(value)[1:] + '\n'))
            if system == 'strict-native':
                corruptions.append(dict(original, stdout=json.dumps(dict(value, closed=0)) + '\n'))
        elif system.startswith('chez-'):
            corruptions.append(dict(original, stdout=original['stdout'].replace(plan['chez_workload_name'], 'equal:1')))
            corruptions.append(dict(original, stdout='ERROR: returned incorrect result: #f\n'))
            corruptions.append(dict(original, stdout=re.sub(r'seconds \([^)]*\)', 'seconds (1e999)', original['stdout'])))
        else:
            corruptions.append(dict(original, stdout=original['stdout'].replace('Result: #t', 'Result: #f')))
        for record in corruptions:
            rejected_frame(plan, system, record)
            rejected += 1
    print('Validated', len(records), 'complete frames and rejected', rejected, 'corruptions')


def launch_with_pending_stop(*arguments, **keywords):
    child = ORIGINAL_POPEN(*arguments, **keywords)
    os.kill(os.getpid(), signal.SIGTERM)
    return child


def interrupted_capture_case(output, owned, name, source, early_stop=False):
    global STOP_REQUESTED
    STOP_REQUESTED = None
    record = dict(command=[sys.executable, '-c', source], status='starting',
                  runner_sha256=digest(Path(__file__)))
    plan = dict(environment={'BINARYEN_CORES': '1'}, timeout_seconds=0.2)
    try:
        if early_stop:
            subprocess.Popen = launch_with_pending_stop
        run_owned_process(plan, dict(cwd=str(output), stdin=None), record, output / (name + '.json'), owned)
    except InterruptedError:
        record['interrupted'] = True
    finally:
        subprocess.Popen = ORIGINAL_POPEN
        STOP_REQUESTED = None
        record['status'] = 'interrupted' if record.get('interrupted') else 'timeout' if record.get('timeout') else 'completed'
        save(output / (name + '.json'), record)
    if not record['cleanup']['leader_reaped'] or not record['cleanup']['capture_handles_closed'] or record['cleanup']['live_members']:
        raise AssertionError('actual owned cleanup failed: ' + name)
    return record


def test_owned_interruption(output, owned):
    global ORIGINAL_POPEN
    output.mkdir(parents=True, exist_ok=False)
    ORIGINAL_POPEN = subprocess.Popen
    before = {number: signal.signal(number, request_stop) for number in (signal.SIGTERM, signal.SIGINT)}
    try:
        initial = interrupted_capture_case(output, owned, 'popen-assignment-window', 'import time; time.sleep(30)', True)
        source = ('import os,signal,sys,time; print("partial-out",flush=True); '
                  'print("partial-err",file=sys.stderr,flush=True); os.kill(os.getppid(),signal.SIGTERM); time.sleep(30)')
        captured = interrupted_capture_case(output, owned, 'interrupted-capture', source)
        timeout = interrupted_capture_case(output, owned, 'timeout-capture', source.replace('os.kill(os.getppid(),signal.SIGTERM); ', ''))
        if not initial.get('interrupted') or not captured.get('interrupted') or not timeout['timeout']:
            raise AssertionError('interruption/timeout decision failed')
        if any(row['stdout'] != 'partial-out\n' or row['stderr'] != 'partial-err\n' for row in (captured, timeout)):
            raise AssertionError('partial stdout/stderr capture was lost')
    finally:
        for number, previous in before.items():
            signal.signal(number, previous)
    print('Validated actual Popen-window interruption, captured interruption and timeout; leaders reaped and handles closed')


if __name__ == '__main__':
    main()
