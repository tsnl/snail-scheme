#!/usr/bin/env python3
"""Verify the frozen complete Ackermann schedule; execution is explicit."""

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
           'rust-native-recursive', 'rust-native-heap', 'rust-wasm-heap')
WORKLOAD = dict(name='ack', count=2, inputs=[3, 12], expected=32765,
                barriers_per_iteration=2)
REJECTED_ENVIRONMENT = ('NODE_OPTIONS', 'NODE_V8_COVERAGE', 'NODE_DEBUG',
    'NODE_DEBUG_NATIVE', 'LD_PRELOAD', 'SNAIL_NATIVE_GC_INTERVAL',
    'SNAIL_GC_STATS', 'SNAIL_GC_HEAP_BYTES', 'SNAIL_GC_MIN_BYTES',
    'CHEZSCHEMELIBDIRS', 'SCHEMEHEAPDIRS')
RECORDED_ENVIRONMENT = (*REJECTED_ENVIRONMENT, 'LD_LIBRARY_PATH', 'LANG', 'LC_ALL', 'TZ')
NUMBER = r'(?:[0-9]+(?:\.[0-9]+)?)(?:[eE][+\-]?[0-9]+)?'
STOP_SIGNAL = None


# ---- Exact commands, complete supervisor imports and frozen identities ----

def save(path, value):
    temporary = path.with_name(path.name + '.pending')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def schedule():
    rows = []
    for round_number in range(-1, 7):
        offset = max(0, round_number)
        order = SYSTEMS[offset:] + SYSTEMS[:offset]
        rows += [dict(benchmark='ack', system=system, round=round_number,
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
    paths = sorted(directory.glob('*.py'))
    if [path.stem for path in paths] != plan['supervisor_modules']:
        raise ValueError('the frozen supervisor module inventory changed')
    for path in paths:
        for name in local_imports(path):
            dependency = directory / (name + '.py')
            if not dependency.is_file() or str(dependency) not in plan['identities']:
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
    base = Path(plan['prepared_directory'])
    prepared = json.loads((base / 'prepared.json').read_text())
    extra = {row['label']: row for row in json.loads((base / 'extra-controls.json').read_text())}
    heap = {row['label']: row for row in json.loads((base / 'heap-and-clock-validation.json').read_text())}
    commands = {
        'production-v8': [prepared['tools']['NODE']['path'], str(base / 'host.mjs'),
                          str(base / 'ack/strict.wasm'), str(base / 'ack/spec.json')],
        'native-final-v8': extra['native-final-v8-full']['command'][:-1],
        'native64': heap['native-timer']['command'],
        'chez-original': extra['original-chez-full']['command'],
        'rust-native-recursive': extra['rust-native-full']['command'],
        'rust-native-heap': heap['rust-native-heap']['command'],
        'rust-wasm-heap': heap['rust-optimized-wasm-heap']['command'],
    }
    expected = {system: dict(command=command, cwd=str(base),
                stdin=str(base / 'ack/input.txt') if system.startswith(('chez-', 'rust-')) else None)
                for system, command in commands.items()}
    if plan['systems'] != expected or set(plan['systems']) != set(SYSTEMS):
        raise ValueError('the seven exact command configurations changed')
    if extra['native-final-v8-full']['command'][-1] != '--validate':
        raise ValueError('native-final validation command framing changed')
    if plan['workload'] != WORKLOAD or json.loads((base / 'ack/spec.json').read_text()) != WORKLOAD:
        raise ValueError('the complete original workload specification changed')
    if (base / 'ack/input.txt').read_text() != '2\n3\n12\n32765\n':
        raise ValueError('the complete original input changed')


def verify_environment(plan):
    for name in REJECTED_ENVIRONMENT:
        if name in os.environ:
            raise ValueError('execution environment must unset ' + name)
    if {name: os.environ.get(name) for name in RECORDED_ENVIRONMENT} != plan['inherited_environment']:
        raise ValueError('recorded inherited environment changed')
    if plan['environment'] != {'BINARYEN_CORES': '1'}:
        raise ValueError('the explicit runtime environment changed')


def verify_execution_constraints(plan):
    if plan['schedule'] != schedule() or len(plan['schedule']) != 56:
        raise ValueError('the fixed balanced schedule changed')
    if plan['cpu'] != 5 or plan['cpu'] not in os.sched_getaffinity(0):
        raise ValueError('CPU 5 is unavailable')
    if plan['timeout_seconds'] != 120:
        raise ValueError('the fixed per-process deadline changed')
    if str(Path(sys.executable).resolve()) != plan['python']:
        raise ValueError('the timing interpreter changed')


def verify(plan):
    verify_execution_constraints(plan)
    verify_environment(plan)
    for path, expected in plan['identities'].items():
        if digest(path) != expected:
            raise ValueError('frozen identity changed: ' + path)
    verify_commands(plan)
    verify_import_closure(plan)
    load_supervisor(plan)


# ---- One complete success frame and finite positive workload clock ----

def output_pattern(system):
    seconds = '(?P<seconds>' + NUMBER + ')'
    if system in ('production-v8', 'native-final-v8'):
        return (r'\{"seconds":' + seconds
                + r',"result":"32765","barriers":null,"setup_barriers":null\}\n')
    if system == 'native64':
        return r'\{"result":"32765","barriers":0,"seconds":' + seconds + r'\}\n'
    if system == 'chez-original':
        return (r'Running ack:3:12:2\nElapsed time: ' + seconds + r' seconds \('
                + '(?P<rounded>' + NUMBER + r')\) for ack:3:12:2\n'
                + r'\+!CSVLINE!\+chez,ack:3:12:2,(?P=seconds)\n')
    if system in ('rust-native-recursive', 'rust-native-heap', 'rust-wasm-heap'):
        return r'Result: 32765\n\+!CSVLINE!\+rust-wasm,ack:2,' + seconds + r'\n'
    raise ValueError('unknown timed system: ' + system)


def positive_seconds(value):
    seconds = float(value)
    if not math.isfinite(seconds) or seconds <= 0:
        raise ValueError('clock is not finite and positive')
    return seconds


def require_successful_process(record):
    if (record['returncode'] != 0 or record['stderr'] or record['timeout']
            or record['executing_descendants'] or record['cleanup']['live_members']):
        raise ValueError('process failed, timed out, wrote stderr or left descendants')
    positive_seconds(record['process_seconds'])


def workload_seconds(system, record):
    require_successful_process(record)
    match = re.fullmatch(output_pattern(system), record['stdout'])
    if not match:
        raise ValueError('complete result or clock framing differs')
    if system == 'chez-original' and not math.isfinite(float(match['rounded'])):
        raise ValueError('Chez rounded clock is not finite')
    return positive_seconds(match['seconds'])


# ---- One owned group through capture, cleanup, leader reap and pipe closure ----

def request_stop(number, frame):
    global STOP_SIGNAL
    STOP_SIGNAL = number


def check_stop():
    if STOP_SIGNAL is not None:
        raise KeyboardInterrupt('received ' + signal.Signals(STOP_SIGNAL).name)


def run_owned(plan, config, record, path, supervisor):
    environment = {**os.environ, **plan['environment']}
    stdin = Path(config['stdin']).read_text() if config['stdin'] else None
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
    config = plan['systems'][scheduled['system']]
    record = dict(scheduled, command=[plan['taskset'], '-c', str(plan['cpu']), *config['command']],
                  cwd=config['cwd'], stdin_path=config['stdin'], status='starting',
                  started=datetime.now(timezone.utc).isoformat(), environment=plan['environment'],
                  diagnostic_only=diagnostic, identities_before='verified')
    save(path, record)
    try:
        run_owned(plan, config, record, path, supervisor)
        check_stop()
        record.update(workload_seconds=workload_seconds(scheduled['system'], record), status='valid')
    except BaseException as error:
        record.update(status='failed', error=repr(error))
        raise
    finally:
        try:
            verify(plan)
            record['identities_after'] = 'verified'
        except BaseException as error:
            record.update(status='failed', identity_after_error=repr(error))
            raise
        finally:
            record['stop_signal'] = STOP_SIGNAL
            save(path, record)
    return record


# ---- Host state, predetermined discards and seven rotating retained rounds ----

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
    for system in SYSTEMS:
        rows = [row for row in samples if row['system'] == system and row['retained']]
        if len(rows) != 7 or {row['position'] for row in rows} != set(range(7)):
            raise ValueError('retained balance differs')
        work, process = [row['workload_seconds'] for row in rows], [row['process_seconds'] for row in rows]
        result[system] = dict(samples=7, workload_median=statistics.median(work),
            workload_range=[min(work), max(work)], process_median=statistics.median(process),
            process_range=[min(process), max(process)])
    return result


def execute(plan, output, diagnostic):
    verify(plan)
    output.mkdir(parents=True, exist_ok=False)
    rows = [dict(benchmark='ack', system=system, retained=False) for system in SYSTEMS] if diagnostic else plan['schedule']
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
            print(index, row['system'], 'validated', flush=True)
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
        try:
            verify(plan)
            report['identities_after'] = 'verified'
        except BaseException as error:
            report.update(complete=False, identity_after_error=repr(error))
            raise
        finally:
            save(output / 'host-after.json', host_snapshot(plan['cpu']))
            save(output / 'campaign.json', report)


def command_line_options():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', type=Path, default=Path(__file__).with_name('timing-plan.json'))
    actions = parser.add_mutually_exclusive_group()
    actions.add_argument('--diagnose', action='store_true', help='one diagnostic timer invocation per exact command')
    actions.add_argument('--run', action='store_true', help='requires the coordinated quiet-window release')
    parser.add_argument('--output', type=Path)
    options = parser.parse_args()
    if not sys.flags.isolated or not sys.dont_write_bytecode:
        parser.error('invoke this runner with python3 -I -B')
    if (options.run or options.diagnose) and options.output is None:
        parser.error('execution requires a new --output directory')
    return options


def main():
    options = command_line_options()
    plan = json.loads(options.plan.read_text())
    if not options.run and not options.diagnose:
        verify(plan)
        print('Verified fixed schedule, identities and supervisor imports; no guest started')
        return
    # Deferred stop requests preserve ownership even during Popen and cleanup.
    # Capture obeys the fixed deadline before SIGINT/SIGTERM stops the campaign.
    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)
    execute(plan, options.output, options.diagnose)


if __name__ == '__main__':
    main()
