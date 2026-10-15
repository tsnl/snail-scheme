#!/usr/bin/env python3
"""Verify the frozen Earley plan; --run requires the parent quiet-window release."""

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
import subprocess
import time


# ---- Frozen identities and strict output framing ----

REJECTED_ENVIRONMENT = ('NODE_OPTIONS', 'NODE_V8_COVERAGE', 'NODE_DEBUG',
    'NODE_DEBUG_NATIVE', 'LD_PRELOAD', 'SNAIL_NATIVE_GC_INTERVAL',
    'SNAIL_GC_STATS', 'SNAIL_GC_HEAP_BYTES', 'SNAIL_GC_MIN_BYTES',
    'EARLEY_SIZE', 'EARLEY_EXPECTED_KIND', 'EARLEY_EXPECTED')
RECORDED_ENVIRONMENT = (*REJECTED_ENVIRONMENT, 'LD_LIBRARY_PATH', 'LANG', 'LC_ALL', 'TZ')


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def verify(plan):
    for path, expected in plan['identities'].items():
        if digest(path) != expected:
            raise ValueError('frozen identity changed: ' + path)
    if plan['cpu'] not in os.sched_getaffinity(0):
        raise ValueError('requested CPU is unavailable')
    if any(name in os.environ for name in REJECTED_ENVIRONMENT):
        raise ValueError('timing environment contains a rejected override')
    if {name: os.environ.get(name) for name in RECORDED_ENVIRONMENT} != plan['inherited_environment']:
        raise ValueError('recorded inherited environment changed')


def json_seconds(system, text):
    value = json.loads(text)
    if text.count('\n') != 1 or not text.endswith('\n'):
        raise ValueError('unexpected JSON framing')
    if system.startswith('v8-'):
        if (set(value) != {'seconds', 'result', 'barriers', 'setup_barriers'} or
                value['result'] != '1' or value['barriers'] is not None or value['setup_barriers'] is not None):
            raise ValueError('unexpected V8 result')
    elif set(value) != {'seconds', 'result'} or value['result'] != 1:
        raise ValueError('unexpected native result')
    return value['seconds']


def scheme_seconds(text):
    number = r'[0-9.eE+\-]+'
    pattern = (rf'Running earley:1\nElapsed time: ({number}) seconds \(({number})\) for earley:1\n'
               rf'\+!CSVLINE!\+chez,earley:1,({number})\n')
    match = re.fullmatch(pattern, text)
    if not match or float(match[1]) != float(match[3]):
        raise ValueError('unexpected Chez result framing')
    return float(match[3])


def workload_seconds(system, record):
    if record['returncode'] != 0 or record['stderr'] or record.get('error'):
        raise ValueError('process failed, timed out or wrote stderr')
    seconds = (scheme_seconds(record['stdout']) if system.startswith('chez-')
               else json_seconds(system, record['stdout']))
    if isinstance(seconds, bool) or not isinstance(seconds, (int, float)) or not math.isfinite(seconds) or seconds < 0:
        raise ValueError('invalid workload duration')
    return seconds


# ---- One owned process group per fresh sample ----

def stop_group(child):
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def running_group_members(group):
    members = []
    for entry in Path('/proc').iterdir():
        if not entry.name.isdecimal():
            continue
        try:
            fields = (entry / 'stat').read_text().rpartition(') ')[2].split()
            if int(fields[2]) == group and fields[0] not in ('Z', 'X'):
                members.append(int(entry.name))
        except (OSError, IndexError, ValueError):
            continue
    return members


def require_stopped_group(group, timeout):
    deadline = time.monotonic() + timeout
    while members := running_group_members(group):
        if time.monotonic() >= deadline:
            raise RuntimeError(f'owned group still has live members: {members}')
        time.sleep(0.01)
    return dict(process_group=group, live_members=[], zombies_count_as_stopped=True)


def capture(child, stdin, timeout):
    try:
        stdout, stderr = child.communicate(stdin, timeout=timeout)
        return dict(stdout=stdout, stderr=stderr, returncode=child.returncode)
    except subprocess.TimeoutExpired as error:
        stop_group(child)
        stdout, stderr = child.communicate(timeout=10)
        return dict(stdout=stdout, stderr=stderr, returncode=child.returncode, error=str(error))


def run_owned_process(plan, config, record, path):
    environment = {**os.environ, **plan['environment'], **config['environment']}
    stdin = Path(config['stdin']).read_text() if config['stdin'] else None
    started = time.perf_counter()
    child = subprocess.Popen(record['command'], cwd=config['cwd'], env=environment,
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        record.update(pid=child.pid, process_group=child.pid, status='running')
        save(path, record)
        record.update(capture(child, stdin, plan['timeout_seconds']))
        save(path, record)
    finally:
        stop_group(child)
        child.wait(timeout=10)
        record['cleanup'] = require_stopped_group(child.pid, plan['group_cleanup_seconds'])
        record['process_seconds'] = time.perf_counter() - started


def sample(plan, scheduled, path):
    verify(plan)
    config = plan['systems'][scheduled['system']]
    command = [plan['taskset'], '-c', str(plan['cpu']), *config['argv']]
    record = dict(scheduled, command=command, cwd=config['cwd'], status='starting',
                  started=datetime.now(timezone.utc).isoformat(),
                  environment={**plan['environment'], **config['environment']},
                  inherited_environment={name: os.environ.get(name) for name in RECORDED_ENVIRONMENT})
    save(path, record)
    try:
        run_owned_process(plan, config, record, path)
        record.update(workload_seconds=workload_seconds(scheduled['system'], record), status='valid')
    except BaseException as error:
        record.update(status='failed', error=repr(error))
        raise
    finally:
        save(path, record)
    return record


# ---- Fixed exclusions and balanced retained rotations ----

def summarize(samples):
    result = {}
    for system in dict.fromkeys(row['system'] for row in samples):
        rows = [row for row in samples if row['system'] == system and row['retained']]
        work, process = [r['workload_seconds'] for r in rows], [r['process_seconds'] for r in rows]
        result[system] = dict(samples=len(rows), workload_median=statistics.median(work),
                              workload_range=[min(work), max(work)],
                              process_median=statistics.median(process), process_range=[min(process), max(process)])
    return result


def campaign(plan, output):
    output.mkdir(parents=True, exist_ok=False)
    report = dict(plan=plan, complete=False, samples=[])
    save(output / 'campaign.json', report)
    try:
        verify(plan)
        for index, scheduled in enumerate(plan['schedule']):
            report['pending_sample'] = dict(index=index, **scheduled)
            save(output / 'campaign.json', report)
            record = sample(plan, scheduled, output / f'sample-{index:02}.json')
            report['samples'].append(record)
            save(output / 'campaign.json', report)
            print(index, scheduled['system'], record['workload_seconds'], flush=True)
        verify(plan)
        report.update(complete=True, summary=summarize(report['samples']))
        report.pop('pending_sample')
    except BaseException as error:
        report['error'] = repr(error)
        raise
    finally:
        save(output / 'campaign.json', report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', type=Path, default=Path(__file__).with_name('timing-plan.json'))
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--output', type=Path)
    options = parser.parse_args()
    plan = json.loads(options.plan.read_text())
    if not options.run:
        verify(plan)
        print('Verified frozen identities; no benchmark process started')
        return
    if options.output is None:
        parser.error('--run requires a new --output directory')
    campaign(plan, options.output)


if __name__ == '__main__':
    main()
