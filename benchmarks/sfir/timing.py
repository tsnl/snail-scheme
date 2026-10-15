#!/usr/bin/env python3
"""Prepare, validate and execute an explicit frozen SFIR comparison protocol."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import sys
import time

import runner


# ---- A fixed first cohort retains every target and control outcome ----

COHORT = ('ack', 'fibfp', 'cat', 'wc', 'ctak', 'fibc')
ROUTES = {'sfir-wasm': 'wasm_validation', 'sfir-native': 'native_validation',
          'chez-original': 'chez_validation', 'chez-adapted': 'chez_adapted_validation',
          'rust-wasm': 'rust_wasm_validation', 'rust-native': 'rust_native_validation'}
OBSERVERS = ('NODE_V8_COVERAGE', 'LD_PRELOAD', 'SNAIL_GC_STATS', 'SNAIL_NATIVE_GC_INTERVAL')


def require_clean_environment(manifest):
    active = [name for name in OBSERVERS if manifest['execution_environment'].get(name)]
    if active:
        raise ValueError(f'clean timing excludes active observation settings: {active}')
    if 'TASKSET' not in manifest['tools']:
        raise ValueError('timing requires an immutable taskset executable')


def protocol_configuration(cpu, warmups, repeats):
    if cpu not in os.sched_getaffinity(0) or warmups != 1 or repeats != 5:
        raise ValueError('choose an allowed CPU; this protocol requires one warmup and five repeats')
    return dict(cpu=cpu, warmups=warmups, repeats=repeats, fresh_processes=True,
                timer='guest monotonic seconds; repeated workload plus complete final predicate',
                excluded='input/setup, result formatting and final resource cleanup',
                rotation='rotate cases by round; rotate six route positions by round plus case position',
                failure_policy='retain all attempts; no retries; any failed warmup/sample withholds route comparisons')


# ---- Copy the selected Rust installation and only locked dependency sources ----

def freeze_tree(source, destination):
    files = [path.relative_to(source) for path in sorted(source.rglob('*')) if path.is_file()]
    if any(path.is_symlink() for path in source.rglob('*')):
        raise ValueError(f'mutable toolchain tree contains symlinks: {source}')
    return runner.freeze_files(source, destination, files)


def select_rust_sysroot(directory, manifest):
    environment = runner.frozen_environment(manifest)
    result = runner.record(directory, 'selected-rust-sysroot', [manifest['tools']['RUSTC']['path'], '--print', 'sysroot'],
                           environment, directory / 'source', manifest['config']['compile_timeout'])
    if not runner.succeeded(result):
        raise RuntimeError('cannot identify the selected Rust sysroot')
    source = Path(result['stdout'].strip())
    if not source.is_dir() or not (source / 'bin/rustc').is_file():
        raise ValueError('selected Rust sysroot is not a complete installation')
    return source


def frozen_rust_tools(directory, manifest, source):
    prefix = Path('toolchain/rust')
    files = freeze_tree(source, directory / prefix)
    manifest['build_dependencies'] = {str(prefix / path): digest for path, digest in files.items()}
    manifest['selected_rust'] = dict(source=str(source), dispatchers={name: manifest['tools'][name] for name in ('RUSTC', 'CARGO')})
    for name in ('RUSTC', 'CARGO'):
        path = directory / prefix / 'bin' / name.lower()
        manifest['tools'][name] = dict(path=str(path), sha256=runner.digest(path), dispatcher=False)
    manifest['execution_environment']['CARGO_HOME'] = str(directory / 'toolchain/cargo-home')


def vendor_locked_crates(directory, manifest):
    # Vendoring reads the existing offline cache once; builds then use only this copy.
    environment = runner.frozen_environment(manifest)
    environment['CARGO_HOME'] = os.environ.get('CARGO_HOME', str(Path.home() / '.cargo'))
    source, destination = directory / 'source', directory / 'toolchain/vendor'
    command = [manifest['tools']['CARGO']['path'], 'vendor', '--offline', '--locked',
               '--manifest-path', source / 'Cargo.toml', '--sync', source / 'benchmarks/wasm-reference/Cargo.toml', destination]
    result = runner.record(directory, 'vendor-locked-crates', command, environment, source, manifest['config']['compile_timeout'])
    if not runner.succeeded(result):
        raise RuntimeError('cannot freeze the locked Rust dependency sources')
    install_vendor_configuration(directory, manifest, result['stdout'])


def install_vendor_configuration(directory, manifest, configuration):
    target = directory / 'toolchain/cargo-home/config.toml'
    target.parent.mkdir(parents=True)
    target.write_text(configuration)
    paths = [target, *(directory / 'toolchain/vendor').rglob('*')]
    for path in paths:
        if path.is_symlink():
            raise ValueError('vendored dependencies must be ordinary files')
        if path.is_file():
            manifest['build_dependencies'][str(path.relative_to(directory))] = runner.digest(path)


def prepare(directory, names, compile_timeout, run_timeout, cpu):
    if not names or len(set(names)) != len(names) or not set(names) <= set(COHORT):
        raise ValueError(f'the first timing cohort is {", ".join(COHORT)}')
    protocol = protocol_configuration(cpu, 1, 5)
    manifest = runner.prepare(runner.ROOT, directory, names, compile_timeout, run_timeout)
    require_clean_environment(manifest)
    frozen_rust_tools(directory, manifest, select_rust_sysroot(directory, manifest))
    vendor_locked_crates(directory, manifest)
    manifest['timing_protocol'] = protocol
    manifest['source_revision'] = subprocess.check_output(['git', '-C', str(runner.ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    runner.save(directory / 'manifest.json', manifest)


# ---- Retain exact execution identities and machine context ----

def machine_context(cpu):
    root = Path(f'/sys/devices/system/cpu/cpu{cpu}')
    files = ('cpufreq/scaling_governor', 'cpufreq/scaling_driver', 'topology/thread_siblings_list')
    return dict(uname=list(os.uname()), affinity=sorted(os.sched_getaffinity(0)), cpu=cpu,
                cpuinfo=Path('/proc/cpuinfo').read_text(),
                configuration={name: (root / name).read_text().strip() for name in files if (root / name).is_file()})


def tool_versions(directory, manifest, environment):
    commands = [('node-v8', 'NODE', ['-p', 'JSON.stringify(process.versions)']), ('chez', 'CHEZ', ['--version']),
                ('rustc', 'RUSTC', ['--version', '--verbose']), ('cargo', 'CARGO', ['--version']),
                ('binaryen', 'WASM_OPT', ['--version']), ('clang', 'CLANG', ['--version'])]
    for label, tool, arguments in commands:
        result = runner.record(directory, 'versions/' + label, [manifest['tools'][tool]['path'], *arguments],
                               environment, directory / 'source', manifest['config']['compile_timeout'])
        if not runner.succeeded(result):
            raise RuntimeError(f'cannot record exact {label} identity')
    runner.save(directory / 'machine.json', machine_context(manifest['timing_protocol']['cpu']))


def copied_artifact(source, destination):
    if source.is_symlink() or not source.is_file():
        raise ValueError(f'timing needs an existing validated artifact: {source}')
    shutil.copy2(source, destination)
    if runner.digest(source) != runner.digest(destination):
        raise ValueError('copied execution artifact changed')


def clean_native_build(directory, source, target, manifest, environment):
    support = directory / 'source/benchmarks/sfir/support'
    for name in ('scalar-provider.h', 'scalar-provider.c', 'scalar-timing-entry.c'):
        shutil.copy2(support / name, target / name)
    header = '#define OBSERVE_BARRIERS 0\n' + runner.native_configuration(runner.load(source / 'spec.json'))
    (target / 'case-config.h').write_text(header)
    command = [manifest['tools']['PYTHON']['path'], directory / 'source/scripts/build-native', '--wasm',
               '--entry-c', target / 'scalar-timing-entry.c', '--c-provider', 'benchmark',
               target / 'scalar-provider.h', target / 'scalar-provider.c', target / 'program.wasm', target / 'program.native']
    return runner.record(target, 'clean-native-build', command, environment, target, manifest['config']['compile_timeout'])


def prepare_case_artifacts(directory, case, status, manifest, environment):
    source = directory / 'source/benchmarks/sfir' / case['name']
    original, target = directory / 'validation' / case['name'], directory / 'timing/artifacts' / case['name']
    target.mkdir(parents=True)
    for name in ('input.txt', 'spec.json', 'program.wasm', 'provider.wasm'):
        if (original / name).exists():
            copied_artifact(original / name, target / name)
    if status.get('native_validation') == 'passed':
        result = clean_native_build(directory, source, target, manifest, environment)
        if not runner.succeeded(result):
            status = dict(status, native_validation='failed-clean-build')
    return target, status


def route_command(directory, case, route, target, manifest):
    tools, support = manifest['tools'], directory / 'source/benchmarks/sfir/support'
    if route == 'sfir-native':
        return [target / 'program.native']
    if route == 'sfir-wasm':
        host = 'reader-timing.mjs' if case['host'] == 'datum-io' else 'scalar-host.mjs'
        tail = [target / 'provider.wasm'] if case['host'] == 'datum-io' else ['--timing']
        return [tools['NODE']['path'], '--no-warnings', support / host, target / 'program.wasm', target / 'spec.json', *tail]
    if route.startswith('chez-'):
        copied_artifact(directory / 'validation' / case['name'] / (route + '.so'), target / (route + '.so'))
        return [tools['CHEZ']['path'], '--program', target / (route + '.so')]
    wasm = route == 'rust-wasm'
    binary = directory / 'rust-target' / ('wasm32-wasip1/release' if wasm else 'release') / (case['name'] + ('.wasm' if wasm else ''))
    copied_artifact(binary, target / (route + ('.wasm' if wasm else '')))
    artifact = target / (route + ('.wasm' if wasm else ''))
    return [tools['NODE']['path'], '--no-warnings', directory / 'source/benchmarks/wasm-reference/run-wasi.mjs', artifact] if wasm else [artifact]


def command_dependencies(directory, command, target):
    paths = [Path(item) for item in command if Path(item).is_absolute() and Path(item).is_file()]
    paths += [target / 'input.txt', target / 'spec.json']
    source = directory / 'source/benchmarks/sfir'
    paths += [source / target.name / 'input.txt', source / target.name / 'spec.json', source / 'runner.py', source / 'timing.py']
    return {str(path.relative_to(directory)): runner.digest(path) for path in paths if directory in path.parents}


def immutable_execution_dependencies(command, target, route, manifest, environment):
    executable = Path(command[0])
    tools = [manifest['tools'][name]['path'] for name in ('NODE', 'CHEZ', 'TASKSET')]
    paths = {path: runner.digest(path) for path in tools}
    result = runner.record(target, route + '-shared-libraries', [manifest['tools']['LDD']['path'], executable],
                           environment, target, manifest['config']['compile_timeout'])
    if not runner.succeeded(result):
        raise RuntimeError(f'{route}: cannot identify actual shared libraries')
    for path in set(re.findall(r'/[^\s()]+', result['stdout'])):
        if not path.startswith('/nix/store/') or not Path(path).is_file():
            raise ValueError(f'execution loads a mutable shared library: {path}')
        paths[path] = runner.digest(path)
    return paths


def prepare_ready_route(directory, case, route, target, row, manifest, environment):
    command = route_command(directory, case, route, target, manifest)
    row.update(command=list(map(str, command)), files=command_dependencies(directory, command, target))
    row['immutable_dependencies'] = immutable_execution_dependencies(command, target, route, manifest, environment)
    if route.startswith('chez-'):
        prefix = Path(manifest['tools']['CHEZ']['path']).parents[1]
        row['immutable_dependencies'].update({str(path): runner.digest(path) for path in prefix.rglob('*.boot')})
    validate_clean_route(directory, row, target, manifest, environment)


# ---- A sample is a successful process with one correct guest timer report ----

def elapsed_seconds(route, output, spec):
    if 'INCORRECT' in output:
        raise ValueError('guest reported an incorrect result')
    if route.startswith('sfir-'):
        rows = [json.loads(line) for line in output.splitlines() if line.startswith('{')]
        if len(rows) != 1 or float(rows[0]['result']) != float(spec['expected']):
            raise ValueError('guest did not report exactly one correct result')
        seconds = rows[0]['seconds']
    else:
        rows = [line.removeprefix('+!CSVLINE!+').split(',') for line in output.splitlines() if line.startswith('+!CSVLINE!+')]
        if len(rows) != 1 or len(rows[0]) != 3 or rows[0][1].split(':')[0] != spec['name'] or rows[0][1].split(':')[-1] != str(spec['count']):
            raise ValueError('guest timer report does not identify the canonical case and count')
        seconds = float(rows[0][2])
    return runner.positive_timeout(seconds)


def execute_attempt(directory, row, target, manifest, environment):
    working = runner.execution_directory(directory, target, 'workload')
    cpu = manifest['timing_protocol']['cpu']
    command = [manifest['tools']['TASKSET']['path'], '-c', str(cpu), *row['command']]
    result = runner.record(target, 'execute', command, environment, working, manifest['config']['run_timeout'],
                           (target / 'input.txt').read_text())
    if not runner.succeeded(result):
        return dict(status='failed-process', record=str((target / 'commands/execute/record.json').relative_to(directory)))
    return checked_sample(directory, row, target, working, result)


def checked_sample(directory, row, target, working, result):
    source = directory / 'source/benchmarks/sfir' / row['case']
    try:
        seconds = elapsed_seconds(row['route'], result['stdout'], runner.load(source / 'spec.json'))
        if not runner.output_files_match(source, working, target, row['route']):
            raise ValueError('complete output bytes differ from the canonical predicate')
        return dict(status='passed', seconds=seconds,
                    record=str((target / 'commands/execute/record.json').relative_to(directory)))
    except (ValueError, TypeError, KeyError, json.JSONDecodeError) as error:
        return dict(status='failed-result', reason=str(error),
                    record=str((target / 'commands/execute/record.json').relative_to(directory)))


def validate_clean_route(directory, row, target, manifest, environment):
    trial = directory / 'timing/clean-validation' / row['case'] / row['route']
    trial.mkdir(parents=True)
    shutil.copy2(target / 'input.txt', trial / 'input.txt')
    result = execute_attempt(directory, row, trial, manifest, environment)
    runner.save(trial / 'result.json', dict(result, performance_sample=False))
    row.update(eligibility='ready' if result['status'] == 'passed' else result['status'], validation=result)


def prepare_route(directory, case, route, target, status, manifest, environment):
    row = dict(case=case['name'], route=route, eligibility=status.get(ROUTES[route], 'not-attempted'),
               correctness_record=f'validation/{case["name"]}/status.json')
    if row['eligibility'] != 'passed':
        return row
    try:
        prepare_ready_route(directory, case, route, target, row, manifest, environment)
    except (OSError, ValueError, RuntimeError) as error:
        row.update(eligibility='failed-clean-preparation', reason=str(error))
    return row


# ---- The frozen schedule never adapts to observed timings or failures ----

def rotated(values, offset):
    offset %= len(values)
    return values[offset:] + values[:offset]


def execution_schedule(cases, rows, protocol):
    eligible = {(row['case'], row['route']) for row in rows if row['eligibility'] == 'ready'}
    schedule = []
    for round_index in range(protocol['warmups'] + protocol['repeats']):
        phase = 'warmup' if round_index < protocol['warmups'] else 'sample'
        for case_index, name in enumerate(rotated(cases, round_index)):
            for route in rotated(list(ROUTES), round_index + case_index):
                if (name, route) in eligible:
                    schedule.append(dict(id=f'{phase}-{round_index}-{name}-{route}', case=name, route=route,
                                         phase=phase, round=round_index))
    return schedule


def build(directory):
    manifest = runner.verify_preparation(directory)
    environment = runner.frozen_environment(manifest)
    tool_versions(directory, manifest, environment)
    validation, rows = runner.validate(directory), []
    for case, status in zip(manifest['cases'], validation['cases'], strict=True):
        target, status = prepare_case_artifacts(directory, case, status, manifest, environment)
        for route in ROUTES:
            rows.append(prepare_route(directory, case, route, target, status, manifest, environment))
    plan = dict(protocol=manifest['timing_protocol'], rows=rows,
                schedule=execution_schedule([case['name'] for case in manifest['cases']], rows, manifest['timing_protocol']))
    runner.save(directory / 'timing/plan.json', plan)
    manifest['timing_plan_sha256'] = runner.digest(directory / 'timing/plan.json')
    runner.save(directory / 'manifest.json', manifest)
    verify_ready(directory)
    return plan


def verify_ready(directory):
    manifest = runner.verify_preparation(directory)
    if runner.digest(directory / 'timing/plan.json') != manifest['timing_plan_sha256']:
        raise ValueError('frozen timing plan changed')
    plan = runner.load(directory / 'timing/plan.json')
    for row in plan['rows']:
        verify_execution_dependencies(directory, row)
    require_clean_environment(manifest)
    return manifest, plan


# ---- Measurements retain interruptions and only compare complete routes ----

def scheduled_attempt(directory, entry, row, manifest, environment):
    verify_execution_dependencies(directory, row)
    runner.verify_files(directory / 'data', manifest['inputs'])
    target = directory / 'timing/measurement' / entry['id']
    target.mkdir(parents=True)
    source = directory / 'source/benchmarks/sfir' / entry['case'] / 'input.txt'
    shutil.copy2(source, target / 'input.txt')
    return dict(entry, **execute_attempt(directory, row, target, manifest, environment))


def verify_execution_dependencies(directory, row):
    runner.verify_files(directory, row.get('files', {}))
    for path, expected in row.get('immutable_dependencies', {}).items():
        if runner.digest(path) != expected:
            raise ValueError(f'executed immutable dependency changed: {path}')


def route_statistics(row, attempts, protocol):
    matching = [item for item in attempts if (item['case'], item['route']) == (row['case'], row['route'])]
    samples = [item['seconds'] for item in matching if item['phase'] == 'sample' and item['status'] == 'passed']
    warmups = [item for item in matching if item['phase'] == 'warmup' and item['status'] == 'passed']
    complete = row['eligibility'] == 'ready' and len(samples) == protocol['repeats'] and len(warmups) == protocol['warmups']
    result = dict(case=row['case'], route=row['route'], eligibility=row['eligibility'], complete=complete, seconds=samples)
    if complete:
        result.update(median=statistics.median(samples), minimum=min(samples), maximum=max(samples))
    return result


def comparison_ratios(rows):
    medians = {(row['case'], row['route']): row['median'] for row in rows if row['complete']}
    ratios = []
    for (case, route), elapsed in medians.items():
        if route.startswith('sfir-'):
            for control in ('chez-original', 'chez-adapted', 'rust-' + route.removeprefix('sfir-')):
                if (case, control) in medians:
                    ratios.append(dict(case=case, numerator=route, denominator=control,
                                       ratio=elapsed / medians[case, control]))
    return ratios


def measurement_passed(report):
    eligible = [row for row in report['rows'] if row['eligibility'] == 'ready']
    return report['status'] == 'complete' and bool(eligible) and all(row['complete'] for row in eligible)


def publish_measurement(directory, report, plan):
    rows = [route_statistics(row, report['attempts'], plan['protocol']) for row in plan['rows']]
    if report['status'] != 'complete':
        for row in rows:
            row['complete'] = False
            row.pop('median', None)
    report.update(rows=rows, ratios=comparison_ratios(rows))
    runner.save(directory / 'timing/measurement.json', report)


def measure(directory, quiet_window):
    manifest, plan = verify_ready(directory)
    if not quiet_window.strip():
        raise ValueError('record the explicit coordinated quiet-window attestation')
    (directory / 'timing/measurement').mkdir()
    environment = runner.frozen_environment(manifest)
    rows = {(row['case'], row['route']): row for row in plan['rows']}
    report = dict(status='running', started_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                  quiet_window=quiet_window, plan_sha256=manifest['timing_plan_sha256'], attempts=[])
    try:
        for entry in plan['schedule']:
            report['attempts'].append(scheduled_attempt(directory, entry, rows[entry['case'], entry['route']], manifest, environment))
            publish_measurement(directory, report, plan)
        verify_ready(directory)
        report['status'] = 'complete'
    except BaseException as error:
        report.update(status='interrupted', reason=repr(error), unattempted=plan['schedule'][len(report['attempts']):])
        raise
    finally:
        report['ended_utc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
        publish_measurement(directory, report, plan)
    return report


# ---- Entry points always hand execution to the copied driver ----

def enter_frozen_driver(directory, action, quiet_window=''):
    manifest = runner.verify_preparation(directory)
    driver = directory / 'source/benchmarks/sfir/timing.py'
    if Path(__file__).resolve() != driver.resolve():
        python = manifest['tools']['PYTHON']['path']
        command = [python, str(driver), action, '--output', str(directory), '--quiet-window', quiet_window]
        os.execv(python, command)


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare', 'build', 'verify', 'measure'))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--benchmarks', nargs='+', default=list(COHORT))
    parser.add_argument('--compile-timeout', type=runner.positive_timeout, default=1200)
    parser.add_argument('--run-timeout', type=runner.positive_timeout, default=1200)
    parser.add_argument('--cpu', type=int, default=2)
    parser.add_argument('--quiet-window', default='')
    return parser.parse_args()


def main():
    args = arguments()
    directory = args.output.resolve()
    if args.action == 'prepare':
        prepare(directory, args.benchmarks, args.compile_timeout, args.run_timeout, args.cpu)
        enter_frozen_driver(directory, 'build')
    enter_frozen_driver(directory, args.action, args.quiet_window)
    if args.action == 'build':
        plan = build(directory)
        rows = [{key: row[key] for key in ('case', 'route', 'eligibility')} for row in plan['rows']]
        print(json.dumps(dict(ready=sum(row['eligibility'] == 'ready' for row in rows), routes=rows), indent=2))
    elif args.action == 'verify':
        verify_ready(directory)
    elif args.action == 'measure':
        report = measure(directory, args.quiet_window)
        print(json.dumps(dict(status=report['status'], rows=report['rows'], ratios=report['ratios']), indent=2))
        if not measurement_passed(report):
            raise SystemExit(1)


# ---- Tests ----

import unittest


class TimingTests(unittest.TestCase):
    def test_complete_schedule_still_fails_when_an_eligible_route_is_incomplete(self):
        report = dict(status='complete', rows=[dict(eligibility='ready', complete=False),
                                             dict(eligibility='unavailable', complete=False)])
        self.assertFalse(measurement_passed(report))
        report['rows'][0]['complete'] = True
        self.assertTrue(measurement_passed(report))
        report['status'] = 'interrupted'
        self.assertFalse(measurement_passed(report))

    def test_changed_execution_input_is_rejected_before_process_launch(self):
        import tempfile
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'input.txt'
            source.write_text('canonical')
            row = dict(files={'input.txt': runner.digest(source)})
            verify_execution_dependencies(root, row)
            source.write_text('different input')
            with self.assertRaisesRegex(ValueError, 'frozen dependency changed'):
                verify_execution_dependencies(root, row)

    def test_schedule_keeps_failed_rows_visible_without_scheduling_them(self):
        rows = [dict(case=name, route=route, eligibility='ready') for name in ('ack', 'cat') for route in ROUTES]
        rows[4]['eligibility'] = 'failed'
        schedule = execution_schedule(['ack', 'cat'], rows, dict(warmups=1, repeats=5))
        self.assertEqual(len(schedule), 11 * 6)
        self.assertFalse(any(item['case'] == 'ack' and item['route'] == 'rust-wasm' for item in schedule))
        self.assertEqual([item['case'] for item in schedule if item['round'] == 1][0], 'cat')

    def test_failed_warmup_or_missing_sample_withholds_comparisons(self):
        row = dict(case='ack', route='sfir-wasm', eligibility='ready')
        attempts = [dict(row, phase='sample', status='passed', seconds=n + 1) for n in range(5)]
        self.assertFalse(route_statistics(row, attempts, dict(warmups=1, repeats=5))['complete'])
        attempts.append(dict(row, phase='warmup', status='passed', seconds=9))
        self.assertEqual(route_statistics(row, attempts, dict(warmups=1, repeats=5))['median'], 3)
        attempts[2]['status'] = 'failed-process'
        self.assertFalse(route_statistics(row, attempts, dict(warmups=1, repeats=5))['complete'])

    def test_timer_reports_require_one_finite_canonical_case(self):
        spec = dict(name='ack', count=2, expected=32765)
        valid = '+!CSVLINE!+chez,ack:3:12:2,0.25\n'
        self.assertEqual(elapsed_seconds('chez-original', valid, spec), 0.25)
        for output in (valid + valid, valid.replace('ack:', 'fib:'), valid.replace(':2,', ':1,'), valid.replace('0.25', 'nan')):
            with self.assertRaises(ValueError):
                elapsed_seconds('chez-original', output, spec)
        with self.assertRaises(ValueError):
            elapsed_seconds('sfir-native', '{"seconds":0.25,"result":42}', spec)


if __name__ == '__main__':
    main()
