#!/usr/bin/env python3
"""Execute the reviewed frozen plan; the default only verifies its identities."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import signal
import statistics
import platform
import subprocess
import sys
import time


# ---- Frozen inputs and strict result framing ----

REJECTED_ENVIRONMENT = ('NODE_OPTIONS', 'NODE_V8_COVERAGE', 'NODE_DEBUG',
    'NODE_DEBUG_NATIVE', 'LD_PRELOAD', 'SNAIL_NATIVE_GC_INTERVAL',
    'SNAIL_GC_STATS', 'SNAIL_GC_HEAP_BYTES', 'SNAIL_GC_MIN_BYTES')
RECORDED_ENVIRONMENT = (*REJECTED_ENVIRONMENT, 'LD_LIBRARY_PATH', 'LANG', 'LC_ALL', 'TZ')


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def supervisor(plan):
    sys.path.insert(0, plan['preparation'])
    import matrix_port
    import data_ports
    for module in (matrix_port, data_ports):
        path = str(Path(module.__file__).resolve())
        if plan['identities'].get(path) != digest(path):
            raise ValueError('unfrozen supervision dependency: ' + path)
    return matrix_port


def verify(plan):
    supervisor(plan)
    for path, expected in plan['identities'].items():
        if digest(path) != expected:
            raise ValueError('frozen identity changed: ' + path)
    if plan['cpu'] not in os.sched_getaffinity(0):
        raise ValueError('requested CPU is unavailable')
    for name in REJECTED_ENVIRONMENT:
        if name in os.environ:
            raise ValueError('timing environment must unset ' + name)
    if {name: os.environ.get(name) for name in RECORDED_ENVIRONMENT} != plan['inherited_environment']:
        raise ValueError('recorded inherited environment changed')


def json_seconds(system, count, text):
    value = json.loads(text)
    if text.count('\n') != 1 or not text.endswith('\n'):
        raise ValueError('unexpected JSON framing')
    if system.startswith('strict-v8'):
        if set(value) != {'seconds', 'result'} or value['result'] != 1:
            raise ValueError('unexpected strict V8 result')
    else:
        if (set(value) != {'seconds', 'result', 'barriers', 'setup_closed', 'worker_closed', 'closed'}
                or value['result'] != 1 or value['barriers'] != 0 or value['setup_closed'] != 1
                or value['worker_closed'] != 0 or value['closed'] != 1):
            raise ValueError('unexpected strict native result or file lifecycle')
    return value['seconds']


def scheme_seconds(benchmark, count, text):
    name, number = f'{benchmark}:{count}', r'[0-9.eE+\-]+'
    pattern = (rf'Running {name}\nElapsed time: ({number}) seconds \(({number})\) for {name}\n'
               rf'\+!CSVLINE!\+chez,{name},({number})\n')
    match = re.fullmatch(pattern, text)
    if not match or float(match[1]) != float(match[3]):
        raise ValueError('unexpected Chez result framing')
    return float(match[3])


def workload_seconds(plan, scheduled, record):
    if record['returncode'] != 0 or record['stderr'] or record['timeout']:
        raise ValueError('process failed, timed out or wrote stderr')
    system, benchmark = scheduled['system'], scheduled['benchmark']
    workload, text = plan['workloads'][benchmark], record['stdout']
    if system.startswith('strict-'):
        seconds = json_seconds(system, workload['count'], text)
    elif system.startswith('chez-'):
        seconds = scheme_seconds(benchmark, workload['count'], text)
    else:
        pattern = (re.escape(workload['rust_result_line'])
                   + rf'\n\+!CSVLINE!\+rust-wasm,{benchmark}:{workload["count"]},([0-9.eE+\-]+)\n')
        match = re.fullmatch(pattern, text)
        if not match:
            raise ValueError('unexpected Rust result framing')
        seconds = float(match[1])
    if isinstance(seconds, bool) or not isinstance(seconds, (int, float)) or not math.isfinite(seconds) or seconds < 0:
        raise ValueError('invalid workload duration')
    return seconds


# ---- One recorded process group per sample ----


def sample(plan, scheduled, path, supervisor):
    verify(plan)
    config = plan['systems'][scheduled['benchmark']][scheduled['system']]
    command = [plan['taskset'], '-c', str(plan['cpu']), *config['argv']]
    record = dict(scheduled, command=command, cwd=config['cwd'], status='starting',
                  started=datetime.now(timezone.utc).isoformat(), environment=plan['environment'],
                  inherited_environment={name: os.environ.get(name) for name in RECORDED_ENVIRONMENT})
    save(path, record)
    try:
        run_owned_process(plan, config, record, path, supervisor)
        record['workload_seconds'] = workload_seconds(plan, scheduled, record)
        record['status'] = 'valid'
    except BaseException as error:
        record.update(status='failed', error=repr(error))
        raise
    finally:
        save(path, record)
    return record


def run_owned_process(plan, config, record, path, supervisor):
    environment = {**os.environ, **plan['environment']}
    environment.pop('NODE_OPTIONS', None)
    stdin = Path(config['stdin']).read_text() if config['stdin'] else None
    started = time.perf_counter()
    child = subprocess.Popen(record['command'], cwd=config['cwd'], env=environment,
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        record.update(pid=child.pid, process_group=child.pid, status='running')
        save(path, record)
        record.update(supervisor.finish_process(child, record['command'], started, plan['timeout_seconds'], stdin))
        save(path, record)
    finally:
        remaining = supervisor.clean_group(child.pid)
        child.wait(timeout=10)
        record['cleanup'] = dict(process_group=child.pid, live_members=remaining, zombies_count_as_stopped=True)
        record['capture_and_cleanup_seconds'] = record.get('process_seconds')
        record['process_seconds'] = time.perf_counter() - started
        if remaining:
            raise RuntimeError(f'owned group still has live members: {remaining}')


# ---- Serial campaign with the predetermined exclusions ----


def summarize(samples):
    result = {}
    for benchmark in dict.fromkeys(row['benchmark'] for row in samples):
        result[benchmark] = {}
        for system in dict.fromkeys(row['system'] for row in samples):
            rows = [row for row in samples if row['benchmark'] == benchmark and row['system'] == system and row['retained']]
            work, process = [r['workload_seconds'] for r in rows], [r['process_seconds'] for r in rows]
            result[benchmark][system] = dict(samples=len(rows), workload_median=statistics.median(work),
                                            workload_range=[min(work), max(work)], process_median=statistics.median(process),
                                            process_range=[min(process), max(process)])
    return result


def host_snapshot(cpu):
    prefix = Path(f'/sys/devices/system/cpu/cpu{cpu}')
    files = [prefix / 'cpufreq' / name for name in ('scaling_driver', 'scaling_governor',
             'scaling_min_freq', 'scaling_max_freq', 'scaling_cur_freq', 'cpuinfo_min_freq', 'cpuinfo_max_freq', 'affected_cpus')]
    files += [prefix / 'topology/thread_siblings_list', Path('/sys/devices/system/cpu/online'),
              Path('/sys/devices/system/cpu/intel_pstate/no_turbo'), Path('/sys/devices/system/cpu/cpufreq/boost')]
    blocks = Path('/proc/cpuinfo').read_text().split('\n\n')
    info = next(block for block in blocks if re.search(rf'^processor\s*:\s*{cpu}$', block, re.M))
    return dict(date=datetime.now(timezone.utc).isoformat(), cpu=cpu, affinity=sorted(os.sched_getaffinity(0)),
                platform=platform.uname()._asdict(), cpuinfo=info, loadavg=os.getloadavg(),
                policy={str(path): path.read_text().strip() if path.exists() else None for path in files})


def campaign(plan, output):
    output.mkdir(parents=True, exist_ok=False)
    report = dict(plan=plan, complete=False, samples=[],
                  inherited_environment={name: os.environ.get(name) for name in RECORDED_ENVIRONMENT})
    save(output / 'campaign.json', report)
    try:
        verify(plan)
        save(output / 'host-before.json', host_snapshot(plan['cpu']))
        owned = supervisor(plan)
        for index, scheduled in enumerate(plan['schedule']):
            report['pending_sample'] = dict(index=index, **scheduled)
            save(output / 'campaign.json', report)
            record = sample(plan, scheduled, output / f'sample-{index:02}.json', owned)
            report['samples'].append(record)
            save(output / 'campaign.json', report)
            print(index, scheduled['benchmark'], scheduled['system'], record['workload_seconds'], flush=True)
        verify(plan)
        report.update(complete=True, summary=summarize(report['samples']))
        report.pop('pending_sample')
    except BaseException as error:
        report['error'] = repr(error)
        raise
    finally:
        save(output / 'host-after.json', host_snapshot(plan['cpu']))
        save(output / 'campaign.json', report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', type=Path, default=Path(__file__).with_name('timing-plan.json'))
    parser.add_argument('--run', action='store_true', help='requires the coordinated quiet-window release')
    parser.add_argument('--output', type=Path)
    options = parser.parse_args()
    plan = json.loads(options.plan.read_text())
    if not options.run:
        verify(plan)
        print('Verified frozen identities; no benchmark process started')
        return
    if options.output is None:
        parser.error('--run requires a new --output directory')
    signal.signal(signal.SIGTERM, interrupted)
    campaign(plan, options.output)


def interrupted(signum, frame):
    raise InterruptedError('campaign interrupted')


if __name__ == '__main__':
    main()
