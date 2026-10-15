#!/usr/bin/env python3
"""Verify the frozen pi/Chudnovsky schedule; execution is always explicit."""

import argparse
import ast
from datetime import datetime, timezone
import hashlib
import inspect
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

SYSTEMS = ('production-v8', 'native-final-v8', 'native64', 'chez-original',
           'chez-adapted', 'chez-limbs', 'rust-native', 'rust-wasm')
WORKLOADS = ('pi', 'chudnovsky')
REJECTED_ENVIRONMENT = ('NODE_OPTIONS', 'NODE_V8_COVERAGE', 'NODE_DEBUG',
    'NODE_DEBUG_NATIVE', 'LD_PRELOAD', 'SNAIL_NATIVE_GC_INTERVAL',
    'SNAIL_GC_STATS', 'SNAIL_GC_HEAP_BYTES', 'SNAIL_GC_MIN_BYTES',
    'SNAIL_INTEGER_TIME', 'CHEZSCHEMELIBDIRS', 'SCHEMEHEAPDIRS')
RECORDED_ENVIRONMENT = (*REJECTED_ENVIRONMENT, 'LD_LIBRARY_PATH', 'LANG', 'LC_ALL', 'TZ')
STOP_SIGNAL = None


# ---- Fixed observations and complete frozen import closure ----

def save(path, value):
    payload = json.dumps(value, indent=2) + '\n'
    temporary = path.with_name(path.name + '.pending')
    temporary.write_text(payload)
    temporary.replace(path)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def schedule():
    rows = []
    for workload in WORKLOADS:
        for round_number in range(-1, 8):
            offset = max(0, round_number)
            order = SYSTEMS[offset:] + SYSTEMS[:offset]
            rows += [dict(benchmark=workload, system=system, round=round_number,
                          position=position, retained=round_number >= 0)
                     for position, system in enumerate(order)]
    return rows


def local_imports(path):
    names = set()
    for node in ast.walk(ast.parse(path.read_text())):
        if isinstance(node, ast.Import):
            names.update(alias.name.split('.')[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            if node.level or not node.module:
                raise ValueError('unexpected relative import: ' + str(path))
            names.add(node.module.split('.')[0])
    return sorted(names - sys.stdlib_module_names)


def verify_import_closure(plan):
    directory = Path(plan['supervisor']).resolve()
    for path in directory.glob('*.py'):
        if any(not (directory / (name + '.py')).is_file() for name in local_imports(path)):
            raise ValueError('incomplete frozen import closure: ' + str(path))


def verify_supervisor_contract(module):
    contract = {'finish_process': ('child', 'command', 'started', 'timeout', 'stdin'),
                'clean_group': ('group',), 'group_members': ('group',)}
    for name, parameters in contract.items():
        helper = getattr(module, name, None)
        if not callable(helper) or tuple(inspect.signature(helper).parameters) != parameters:
            raise ValueError('supervisor contract changed: ' + name)


def load_supervisor(plan):
    directory = Path(plan['supervisor']).resolve()
    if sys.path[0] != str(directory):
        sys.path.insert(0, str(directory))
    import matrix_port
    import data_ports
    for module in (matrix_port, data_ports):
        if Path(module.__file__).resolve().parent != directory:
            raise ValueError('supervisor loaded outside the frozen directory')
    verify_supervisor_contract(matrix_port)
    return matrix_port


def verify_commands(plan):
    original = json.loads(Path(plan['original_plan']).read_text())
    systems = {name: {row['system']: row for row in original['commands'] if row['name'] == name}
               for name in WORKLOADS}
    if plan['systems'] != systems or any(set(rows) != set(SYSTEMS) for rows in systems.values()):
        raise ValueError('the sixteen exact original command configurations changed')
    for name in WORKLOADS:
        specification = Path(systems[name]['production-v8']['command'][3])
        if plan['workloads'][name] != json.loads(specification.read_text()):
            raise ValueError('the complete workload specification changed: ' + name)


def verify_environment(plan):
    for name in REJECTED_ENVIRONMENT:
        if name in os.environ:
            raise ValueError('execution environment must unset ' + name)
    if {name: os.environ.get(name) for name in RECORDED_ENVIRONMENT} != plan['inherited_environment']:
        raise ValueError('recorded inherited environment changed')
    if plan['environment'] != {'BINARYEN_CORES': '1'}:
        raise ValueError('the explicit runtime environment changed')


def verify(plan):
    if plan['schedule'] != schedule() or len(plan['schedule']) != 144:
        raise ValueError('the fixed balanced schedule changed')
    if plan['cpu'] != 5 or plan['cpu'] not in os.sched_getaffinity(0):
        raise ValueError('CPU 5 is unavailable')
    verify_environment(plan)
    for path, expected in plan['identities'].items():
        if digest(path) != expected:
            raise ValueError('frozen identity changed: ' + path)
    verify_commands(plan)
    load_supervisor(plan)


# ---- Exact full numerical output precedes one finite workload clock ----

def output_pattern(plan, scheduled):
    name, system = scheduled['benchmark'], scheduled['system']
    workload = plan['workloads'][name]
    prefix, family, label = workload['output'], 'snail-integer', name
    if system == 'native64':
        label = 'native'
    elif system.startswith('chez-'):
        family = 'chez-integer'
    elif system.startswith('rust-'):
        prefix, family = 'Result: ' + prefix, 'rust-wasm'
    return (re.escape(prefix + f'+!CSVLINE!+{family},{label}:{workload["count"]},')
            + r'([0-9.eE+\-]+)\n')


def workload_seconds(plan, scheduled, record):
    if (record['returncode'] != 0 or record['stderr'] or record['timeout']
            or record['executing_descendants'] or record['cleanup']['live_members']):
        raise ValueError('process failed, timed out, wrote stderr or left descendants')
    match = re.fullmatch(output_pattern(plan, scheduled), record['stdout'])
    if not match:
        raise ValueError('complete numerical output or clock framing differs')
    seconds = float(match[1])
    if not math.isfinite(seconds) or seconds < 0:
        raise ValueError('workload clock is not finite and nonnegative')
    return seconds


# ---- One recorded process group, captured and stopped before the next row ----

def request_stop(number, frame):
    global STOP_SIGNAL
    STOP_SIGNAL = number


def check_stop():
    if STOP_SIGNAL is not None:
        raise KeyboardInterrupt('received ' + signal.Signals(STOP_SIGNAL).name)


def run_owned(plan, config, record, path, supervisor):
    environment = {**os.environ, **plan['environment'], **config.get('environment', {})}
    stdin = Path(config['stdin']).read_text() if config.get('stdin') else None
    started = time.perf_counter()
    check_stop()
    child = subprocess.Popen(record['command'], cwd=config['cwd'], env=environment,
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        record.update(pid=child.pid, process_group=child.pid, status='running')
        save(path, record)
        check_stop()
        record.update(supervisor.finish_process(child, record['command'], started,
                                               plan['timeout_seconds'], stdin))
        check_stop()
    except BaseException:
        supervisor.clean_group(child.pid)
        stdout, stderr = child.communicate(timeout=10)
        record.update(returncode=child.returncode, stdout=stdout, stderr=stderr)
        raise
    finally:
        remaining = supervisor.clean_group(child.pid)
        child.wait(timeout=10)
        for pipe in (child.stdin, child.stdout, child.stderr):
            if pipe is not None:
                pipe.close()
        record['cleanup'] = dict(process_group=child.pid, live_members=remaining,
                                 leader_reaped=True, capture_handles_closed=True,
                                 zombies_count_as_stopped=True)
        record['process_seconds'] = time.perf_counter() - started
        if remaining:
            raise RuntimeError('owned group remains live: ' + str(remaining))


def sample(plan, scheduled, path, supervisor, diagnostic):
    verify(plan)
    config = plan['systems'][scheduled['benchmark']][scheduled['system']]
    record = dict(scheduled, command=[plan['taskset'], '-c', str(plan['cpu']), *config['command']],
                  cwd=config['cwd'], status='starting', started=datetime.now(timezone.utc).isoformat(),
                  environment={**plan['environment'], **config.get('environment', {})},
                  diagnostic_only=diagnostic)
    save(path, record)
    try:
        run_owned(plan, config, record, path, supervisor)
        check_stop()
        record.update(workload_seconds=workload_seconds(plan, scheduled, record), status='valid')
    except BaseException as error:
        record.update(status='failed', error=repr(error))
        raise
    finally:
        record['stop_signal'] = STOP_SIGNAL
        save(path, record)
    return record


# ---- Host state, predetermined discards and retained failures ----

def host_snapshot(cpu):
    prefix = Path(f'/sys/devices/system/cpu/cpu{cpu}')
    files = [prefix / 'cpufreq' / name for name in ('scaling_driver', 'scaling_governor',
             'scaling_min_freq', 'scaling_max_freq', 'scaling_cur_freq', 'affected_cpus')]
    files += [prefix / 'topology/thread_siblings_list', Path('/sys/devices/system/cpu/online'),
              Path('/sys/devices/system/cpu/intel_pstate/no_turbo'), Path('/sys/devices/system/cpu/cpufreq/boost')]
    blocks = Path('/proc/cpuinfo').read_text().split('\n\n')
    info = next(block for block in blocks if re.search(rf'^processor\s*:\s*{cpu}$', block, re.M))
    return dict(date=datetime.now(timezone.utc).isoformat(), cpu=cpu, affinity=sorted(os.sched_getaffinity(0)),
                platform=platform.uname()._asdict(), cpuinfo=info, loadavg=os.getloadavg(),
                inherited_environment={name: os.environ.get(name) for name in RECORDED_ENVIRONMENT},
                policy={str(path): path.read_text().strip() if path.exists() else None for path in files})


def summarize(samples):
    result = {}
    for name in WORKLOADS:
        result[name] = {}
        for system in SYSTEMS:
            rows = [row for row in samples if row['benchmark'] == name and row['system'] == system and row['retained']]
            if len(rows) != 8 or {row['position'] for row in rows} != set(range(8)):
                raise ValueError('retained balance differs')
            work, process = [row['workload_seconds'] for row in rows], [row['process_seconds'] for row in rows]
            result[name][system] = dict(samples=8, workload_median=statistics.median(work),
                workload_range=[min(work), max(work)], process_median=statistics.median(process),
                process_range=[min(process), max(process)])
    return result


def execute(plan, output, diagnostic):
    verify(plan)
    verify_import_closure(plan)
    output.mkdir(parents=True, exist_ok=False)
    rows = [dict(benchmark=name, system=system, retained=False)
            for name in WORKLOADS for system in SYSTEMS] if diagnostic else plan['schedule']
    report = dict(plan=plan, complete=False, diagnostic_only=diagnostic, samples=[])
    save(output / 'campaign.json', report)
    save(output / 'host-before.json', host_snapshot(plan['cpu']))
    supervisor = load_supervisor(plan)
    try:
        for index, row in enumerate(rows):
            check_stop()
            report['pending_sample'] = dict(index=index, **row)
            save(output / 'campaign.json', report)
            record = sample(plan, row, output / f'sample-{index:03}.json', supervisor, diagnostic)
            report['samples'].append(record)
            save(output / 'campaign.json', report)
            print(index, row['benchmark'], row['system'], 'validated', flush=True)
        check_stop()
        verify(plan)
        report.update(complete=True)
        if not diagnostic:
            report['summary'] = summarize(report['samples'])
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
    actions = parser.add_mutually_exclusive_group()
    actions.add_argument('--diagnose', action='store_true', help='one diagnostic timer invocation per exact command')
    actions.add_argument('--run', action='store_true', help='requires the coordinated quiet-window release')
    parser.add_argument('--output', type=Path)
    options = parser.parse_args()
    plan = json.loads(options.plan.read_text())
    if not options.run and not options.diagnose:
        verify(plan)
        verify_import_closure(plan)
        print('Verified fixed schedule, identities and supervisor imports; no guest started')
        return
    if options.output is None:
        parser.error('execution requires a new --output directory')
    # Handlers request a stop without interrupting Popen's ownership transition
    # or cleanup. Capture honors its fixed deadline before the stop is recorded.
    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)
    execute(plan, options.output, options.diagnose)


if __name__ == '__main__':
    main()
