#!/usr/bin/env python3
"""Prepare, validate and execute an explicit frozen SFIR comparison protocol."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import statistics
import sys
import time

import runner


# ---- The selected corpus retains every target and control outcome ----

ROUTES = {'sfir-wasm': 'wasm_validation', 'sfir-native': 'native_validation',
          'chez-original': 'chez_validation', 'chez-adapted': 'chez_adapted_validation',
          'rust-wasm': 'rust_wasm_validation', 'rust-native': 'rust_native_validation'}
OBSERVERS = ('NODE_OPTIONS', 'NODE_V8_COVERAGE', 'LD_PRELOAD', 'SNAIL_GC_STATS', 'SNAIL_NATIVE_GC_INTERVAL')


def require_clean_environment(manifest):
    active = {name: manifest['execution_environment'][name] for name in OBSERVERS if manifest['execution_environment'].get(name)}
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


def prepare(directory, names, compile_timeout, run_timeout, cpu):
    if not names:
        raise ValueError('choose at least one corpus workload')
    protocol = protocol_configuration(cpu, 1, 5)
    manifest = runner.prepare(runner.ROOT, directory, names, compile_timeout, run_timeout)
    require_clean_environment(manifest)
    manifest['timing_protocol'] = protocol
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


def clean_native_sources(directory, case, source, target):
    support = directory / 'source/benchmarks/sfir/support'
    kind = 'integer' if case['host'] == 'integer' else 'scalar'
    for name in (kind + '-provider.h', kind + '-provider.c', kind + '-timing-entry.c'):
        shutil.copy2(support / name, target / name)
    header = target / ('integer-provider.h' if kind == 'integer' else 'case-config.h')
    configuration = header.read_text() if kind == 'integer' else runner.native_configuration(runner.load(source / 'spec.json'))
    header.write_text('#define OBSERVE_BARRIERS 0\n' + configuration)
    return kind


def clean_native_build(directory, case, source, target, manifest, environment):
    kind = clean_native_sources(directory, case, source, target)
    command = [manifest['tools']['PYTHON']['path'], directory / 'source/scripts/build-native', '--wasm',
               '--entry-c', target / (kind + '-timing-entry.c'), '--c-provider', 'benchmark',
               target / (kind + '-provider.h'), target / (kind + '-provider.c'), target / 'program.wasm.raw.wasm', target / 'program.native']
    if case['name'] == 'fft':
        runner.fft_provider(directory, target, manifest, environment, False)
        command[2:2] = ['--c-provider', 'math', directory / 'source/benchmarks/sfir/support/fft-math.h', target / 'math-provider.o']
    return runner.record(target, 'clean-native-build', command, environment, target, manifest['config']['compile_timeout'])


def prepare_case_artifacts(directory, case, status, manifest, environment):
    source = directory / 'source/benchmarks/sfir' / case['name']
    original, target = directory / 'validation' / case['name'], directory / 'timing/artifacts' / case['name']
    target.mkdir(parents=True)
    for name in ('input.txt', 'spec.json', 'program.wasm', 'program.wasm.raw.wasm', 'provider.wasm',
                 'math-provider.wasm', 'native-input.txt'):
        if (original / name).exists():
            copied_artifact(original / name, target / name)
    if status.get('native_validation') == 'passed':
        status = prepare_clean_native(directory, case, source, target, status, manifest, environment)
    return target, status


def prepare_clean_native(directory, case, source, target, status, manifest, environment):
    try:
        result = clean_native_build(directory, case, source, target, manifest, environment)
        parity = runner.native_build_status(target, result, status)
        if parity == 'passed':
            return status
        return dict(status, native_validation='failed-clean-' + parity.removeprefix('failed-'))
    except (OSError, ValueError, RuntimeError) as error:
        runner.save(target / 'clean-native-preparation.json', dict(status='failed', reason=str(error)))
        return dict(status, native_validation='failed-clean-preparation')


def clean_wasm_command(directory, case, target, tools):
    # Each host spells its actual scalar ABI; validation-only observers stay absent.
    host = case['host']
    if host == 'scalar':
        name, tail = 'scalar-host.mjs', ['--timing']
    elif host == 'integer':
        name, tail = 'integer-timing.mjs', []
    elif host in ('nucleic', 'tail', 'ray'):
        name, tail = host + '-host.mjs', ['--timing', target / 'provider.wasm']
    elif host in ('datum-io', 'compiler', 'dynamic', 'scheme', 'slatex'):
        name, tail = 'reader-timing.mjs', [target / 'provider.wasm']
    else:
        raise ValueError(f'no clean Wasm host for {host}')
    return [tools['NODE']['path'], '--no-warnings', directory / 'source/benchmarks/sfir/support' / name,
            target / 'program.wasm', target / 'spec.json', *tail]


def decimal_timing_source(source, adapter):
    text, invocation = source.read_text(), '(run-benchmark)\n'
    if not text.endswith(invocation):
        raise ValueError('decimal control must end with one explicit benchmark invocation')
    return text[:-len(invocation)] + adapter.read_text()


def clean_chez_artifact(directory, case, route, target, manifest, environment):
    original = directory / 'validation' / case['name'] / (route + '.so')
    if case['host'] != 'integer':
        copied_artifact(original, target / (route + '.so'))
        return
    source = directory / 'source/benchmarks/sfir' / case['name'] / (route + '.scm')
    adapter = directory / 'source/benchmarks/sfir/support/decimal-timing.scm'
    (target / (route + '.scm')).write_text(decimal_timing_source(source, adapter))
    result = runner.compile_chez_control(target, target, manifest, environment, route.removeprefix('chez-'))
    if not runner.succeeded(result):
        raise RuntimeError('decimal timing control failed to compile')


def route_command(directory, case, route, target, manifest, environment):
    tools = manifest['tools']
    if route == 'sfir-native':
        return [target / 'program.native', *([target / 'native-input.txt'] if case['host'] == 'integer' else [])]
    if route == 'sfir-wasm':
        return clean_wasm_command(directory, case, target, tools)
    if route.startswith('chez-'):
        clean_chez_artifact(directory, case, route, target, manifest, environment)
        return [tools['CHEZ']['path'], '--program', target / (route + '.so')]
    wasm = route == 'rust-wasm'
    binary = directory / 'rust-target' / ('wasm32-wasip1/release' if wasm else 'release') / (case['name'] + ('.wasm' if wasm else ''))
    copied_artifact(binary, target / (route + ('.wasm' if wasm else '')))
    artifact = target / (route + ('.wasm' if wasm else ''))
    return [tools['NODE']['path'], '--no-warnings', directory / 'source/benchmarks/wasm-reference/run-wasi.mjs', artifact] if wasm else [artifact]


def command_dependencies(directory, command, target):
    paths = [Path(item) for item in command if Path(item).is_absolute() and Path(item).is_file()]
    paths += [target / 'input.txt', target / 'spec.json']
    paths += [target / name for name in ('math-provider.wasm', 'native-input.txt', 'chez-original.scm', 'chez-adapted.scm')
              if (target / name).is_file()]
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
    command = route_command(directory, case, route, target, manifest, environment)
    row.update(command=list(map(str, command)), files=command_dependencies(directory, command, target))
    if route == 'sfir-native':
        row['native_parity'] = checked_native_parity(directory, target, row)
    row['immutable_dependencies'] = immutable_execution_dependencies(command, target, route, manifest, environment)
    if route.startswith('chez-'):
        prefix = Path(manifest['tools']['CHEZ']['path']).parents[1]
        row['immutable_dependencies'].update({str(path): runner.digest(path) for path in prefix.rglob('*.boot')})
    validate_clean_route(directory, row, target, manifest, environment)


def checked_native_parity(directory, target, row):
    report = runner.load(target / 'native-parity.json')
    required = {'program.wasm.raw.wasm', 'program.wasm', 'program.native'}
    if report['status'] != 'passed' or not required <= report['files'].keys():
        raise ValueError('timing requires verified native optimized-program parity')
    runner.verify_files(target, report['files'])
    expected = dict(raw_sha256=report['files']['program.wasm.raw.wasm'], optimized_sha256=report['files']['program.wasm'])
    runner.check_native_parity(target, expected, report['files'])
    paths = [target / name for name in report['files'] if not name.endswith('module.ll')]
    paths += [target / 'native-parity.json']
    row['files'].update({str(path.relative_to(directory)): runner.digest(path) for path in paths})
    return report


# ---- A sample is a successful process with one correct guest timer report ----

def sfir_elapsed(output, spec):
    rows = [json.loads(line) for line in output.splitlines() if line.startswith('{')]
    if len(rows) != 1:
        raise ValueError('guest did not report exactly one correct result')
    expected = 1 if isinstance(spec['expected'], list) else spec['expected']
    result = rows[0]['result']
    correct = float(result) == expected if isinstance(expected, float) else str(result) == str(expected)
    if not correct:
        raise ValueError('guest did not report exactly one correct result')
    return rows[0]['seconds']


def timer_name_matches(route, name, spec):
    canonical = spec.get('timer_names', {}).get(route.split('-')[0])
    if canonical:
        return name == canonical
    parts = name.split(':')
    return parts[0] == spec['name'] and parts[-1] == str(spec['count'])


def control_elapsed(route, output, spec):
    rows = [line.removeprefix('+!CSVLINE!+').split(',') for line in output.splitlines() if line.startswith('+!CSVLINE!+')]
    if len(rows) != 1 or len(rows[0]) != 3:
        raise ValueError('guest timer report does not identify the canonical case and count')
    if not timer_name_matches(route, rows[0][1], spec):
        raise ValueError('guest timer report does not identify the canonical case and count')
    return float(rows[0][2])


def check_decimal_output(route, output, spec):
    if 'output' not in spec:
        return
    marker = '{' if route.startswith('sfir-') else '+!CSVLINE!+'
    observed = ''.join(line for line in output.splitlines(keepends=True) if not line.startswith(marker))
    expected = ('Result: ' if route.startswith('rust-') else '') + spec['output']
    if observed.encode('utf-8') != expected.encode('utf-8'):
        raise ValueError('complete decimal output bytes differ from the canonical predicate')


def elapsed_seconds(route, output, spec):
    if 'INCORRECT' in output:
        raise ValueError('guest reported an incorrect result')
    check_decimal_output(route, output, spec)
    seconds = sfir_elapsed(output, spec) if route.startswith('sfir-') else control_elapsed(route, output, spec)
    return runner.positive_timeout(seconds)


def execute_attempt(directory, row, target, manifest, environment):
    source = directory / 'source/benchmarks/sfir' / row['case']
    working = runner.workload_execution_directory(directory, source, target, 'workload')
    active = dict(environment, **row.get('execution_environment', {}))
    cpu = manifest['timing_protocol']['cpu']
    command = [manifest['tools']['TASKSET']['path'], '-c', str(cpu), *row['command']]
    result = runner.record(target, 'execute', command, active, working, manifest['config']['run_timeout'],
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
               correctness_record=f'validation/{case["name"]}/status.json', execution_environment={})
    spec = runner.load(target / 'spec.json')
    if route == 'sfir-native' and 'native_heap_bytes' in spec:
        row['execution_environment']['SNAIL_GC_HEAP_BYTES'] = str(spec['native_heap_bytes'])
    if row['eligibility'] != 'passed':
        return row
    try:
        prepare_ready_route(directory, case, route, target, row, manifest, environment)
    except (OSError, ValueError, RuntimeError, KeyError) as error:
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
    parser.add_argument('--benchmarks', nargs='+', default=['all'])
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
    def test_node_options_cannot_instrument_a_clean_route(self):
        manifest = dict(tools={'TASKSET': dict(path='/immutable/taskset')}, execution_environment={'NODE_OPTIONS': '--cpu-prof'})
        with self.assertRaisesRegex(ValueError, 'NODE_OPTIONS.*--cpu-prof'):
            require_clean_environment(manifest)
        self.assertEqual(manifest['execution_environment']['NODE_OPTIONS'], '--cpu-prof')
        manifest['execution_environment']['NODE_OPTIONS'] = ''
        require_clean_environment(manifest)

    def test_full_corpus_routes_have_explicit_clean_hosts(self):
        corpus = runner.load(runner.CORPUS / 'corpus.json')
        cases = runner.selected_cases(corpus, ['all'])
        self.assertEqual(len(cases), 57)
        for case in cases:
            command = clean_wasm_command(Path('/frozen'), case, Path('/artifact'), {'NODE': dict(path='/node')})
            self.assertNotIn('verify.mjs', ' '.join(map(str, command)))
            self.assertNotIn('--validate', command)
        with self.assertRaisesRegex(ValueError, 'no clean Wasm host'):
            clean_wasm_command(Path('/frozen'), dict(host='unknown'), Path('/artifact'), {'NODE': dict(path='/node')})

    def test_integer_results_do_not_lose_bits_and_sequence_predicates_return_flags(self):
        spec = dict(name='large', count=1, expected=9007199254740993)
        self.assertEqual(elapsed_seconds('sfir-native', '{"result":"9007199254740993","seconds":0.1}', spec), 0.1)
        with self.assertRaises(ValueError):
            elapsed_seconds('sfir-native', '{"result":"9007199254740992","seconds":0.1}', spec)
        spec['expected'] = [1, 2, 3]
        self.assertEqual(elapsed_seconds('sfir-wasm', '{"result":"1","seconds":0.1}', spec), 0.1)

    def test_array1_and_equal_keep_the_controls_actual_timer_names(self):
        for name in ('array1', 'equal'):
            spec = runner.load(runner.CORPUS / name / 'spec.json')
            for route in ('chez-original', 'rust-native', 'rust-wasm'):
                identity = spec['timer_names'][route.split('-')[0]]
                output = f'+!CSVLINE!+control,{identity},0.1\n'
                self.assertEqual(elapsed_seconds(route, output, spec), 0.1)
                with self.assertRaises(ValueError):
                    elapsed_seconds(route, output.replace(identity, identity + ':1'), spec)

    def test_decimal_routes_require_every_output_byte(self):
        spec = dict(name='pi', count=2, expected=['123', '-4'], output='(123 -4)\n')
        for route in ROUTES:
            timer = '{"result":"1","seconds":0.1}\n' if route.startswith('sfir-') else '+!CSVLINE!+control,pi:2,0.1\n'
            output = ('Result: ' if route.startswith('rust-') else '') + spec['output'] + timer
            self.assertEqual(elapsed_seconds(route, output, spec), 0.1)
            for changed in (output.replace('-4', '-5'), output.replace(')\n', ')\r\n'), output + 'extra\n'):
                with self.assertRaisesRegex(ValueError, 'complete decimal output bytes'):
                    elapsed_seconds(route, changed, spec)

    def test_native_route_rejects_incomplete_or_failed_parity_evidence(self):
        import tempfile
        with tempfile.TemporaryDirectory() as temporary:
            root, row = Path(temporary), dict(files={})
            target = root / 'timing/artifacts/ack'
            target.mkdir(parents=True)
            (target / 'program.wasm.raw.wasm').write_bytes(b'raw compiler output')
            for status in ('passed', 'failed-parity'):
                runner.save(target / 'native-parity.json', dict(status=status, files={
                    'program.wasm.raw.wasm': runner.digest(target / 'program.wasm.raw.wasm')}))
                with self.assertRaisesRegex(ValueError, 'verified native optimized-program parity'):
                    checked_native_parity(root, target, row)

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


@unittest.skipUnless(all(shutil.which(name) for name in ('node', 'wasm-as', 'clang', 'scheme', 'taskset')),
                     'clean host execution probes need Node, Binaryen, Clang, Chez and taskset')
class CleanHostTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import tempfile
        output = runner.ROOT / 'build/sfir-timing-probes'
        output.mkdir(parents=True, exist_ok=True)
        cls.directory = Path(tempfile.mkdtemp(prefix='attempt-', dir=output))
        support = cls.directory / 'source/benchmarks/sfir/support'
        shutil.copytree(runner.CORPUS / 'support', support)
        (cls.directory / 'data/inputs').mkdir(parents=True)
        cls.environment = dict(os.environ, BINARYEN_CORES='1')

    def probe_directory(self, name):
        path = self.directory / name
        path.mkdir()
        return path

    def record_probe(self, target, label, command, stdin=None):
        return runner.record(target, label, command, self.environment, target, 30, stdin)

    def assemble(self, target, name, text):
        source, artifact = target / (name + '.wat'), target / (name + '.wasm')
        source.write_text(text)
        result = self.record_probe(target, 'assemble-' + name, [shutil.which('wasm-as'), source, '-o', artifact])
        self.assertTrue(runner.succeeded(result), result)
        return artifact

    def runtime_provider(self, target):
        return self.assemble(target, 'provider', '''(module
          (memory (export "memory") 1)
          (func (export "_initialize"))
          (func (export "snail:io/close-all") (result i32) (i32.const 0)))''')

    def run_wasm_probe(self, target, host, spec, text):
        self.assemble(target, 'program', text)
        runner.save(target / 'spec.json', spec)
        command = clean_wasm_command(self.directory, dict(host=host), target,
                                     {'NODE': dict(path=shutil.which('node'))})
        result = self.record_probe(target, 'execute', command)
        self.assertTrue(runner.succeeded(result), result)
        self.assertGreater(elapsed_seconds('sfir-wasm', result['stdout'], spec), 0)

    def test_runtime_host_categories_use_typed_inputs_without_diagnostic_exports(self):
        text = '''(module
          (import "benchmark" "input_i64" (func $integer (param i32) (result i64)))
          (import "benchmark" "input_f64" (func $real (param i32) (result f64)))
          (import "benchmark" "barrier" (func $barrier (result i32)))
          (func (export "main"))
          (func (export "configured-count") (result i64) (i64.const 2))
          (func (export "bench") (param i64) (result i64)
            (if (i64.ne (call $integer (i32.const 0)) (i64.const 7)) (then unreachable))
            (if (f64.ne (call $real (i32.const 1)) (f64.const 2.5)) (then unreachable))
            (drop (call $barrier)) (i64.const 1)))'''
        spec = dict(name='typed-runtime-probe', inputs=[7, 2.5], count=2, expected=1)
        for host in ('datum-io', 'compiler', 'dynamic', 'scheme', 'slatex', 'nucleic'):
            with self.subTest(host=host):
                target = self.probe_directory(host)
                self.runtime_provider(target)
                self.run_wasm_probe(target, host, spec, text)

    def test_file_hosts_preserve_their_distinct_path_arities(self):
        for host in ('tail', 'ray'):
            with self.subTest(host=host):
                target = self.probe_directory(host)
                self.runtime_provider(target)
                indexed = host == 'tail'
                length_type = '(param i32)' if indexed else ''
                character_type = '(param i32 i64)' if indexed else '(param i64)'
                length_args = '(i32.const 0)' if indexed else ''
                character_args = '(i32.const 0) (i64.const 0)' if indexed else '(i64.const 0)'
                text = f'''(module
                  (import "benchmark" "path_length" (func $length {length_type} (result i64)))
                  (import "benchmark" "path_character" (func $character {character_type} (result i32)))
                  (func (export "main"))
                  (func (export "bench") (param i64) (result i64)
                    (if (i64.ne (call $length {length_args}) (i64.const 1)) (then unreachable))
                    (if (i32.ne (call $character {character_args}) (i32.const 97)) (then unreachable))
                    (i64.const 1)))'''
                spec = dict(name=host, inputs=[], count=2, expected=1, pathname='a', pathnames=['a', 'b'])
                self.run_wasm_probe(target, host, spec, text)

    def test_scalar_sequence_predicate_and_math_provider_execute(self):
        target = self.probe_directory('scalar-vector')
        text = '''(module
          (import "benchmark" "vector_i64" (func $input (param i32 i64) (result i64)))
          (import "benchmark" "expected_i64" (func $expected (param i64) (result i64)))
          (func (export "main"))
          (func (export "bench") (param i64) (result i64)
            (if (i64.ne (call $input (i32.const 0) (i64.const 1))
                        (call $expected (i64.const 1))) (then unreachable)) (i64.const 1)))'''
        spec = dict(name='vector-probe', inputs=[[3, 4]], count=2, expected=[3, 4], result_kind='i64-vector-values')
        self.run_wasm_probe(target, 'scalar', spec, text)
        target = self.probe_directory('scalar-math')
        self.assemble(target, 'math-provider', '(module (func (export "snail_sin") (param f64) (result f64) (local.get 0)))')
        text = '''(module (import "math" "snail_sin" (func $sin (param f64) (result f64)))
          (func (export "main"))
          (func (export "bench") (param i64) (result f64) (call $sin (f64.const 0))))'''
        spec = dict(name='math-probe', inputs=[], count=2, expected=0.0, math_provider='math-provider.wasm')
        self.run_wasm_probe(target, 'scalar', spec, text)

    def test_decimal_wasm_host_checks_text_after_the_flag(self):
        target = self.probe_directory('integer-wasm')
        output = '(123)\n'
        emit = ' '.join(f'(call $emit (i32.const {ord(char)}))' for char in output)
        text = f'''(module
          (import "benchmark" "expected_character" (func $expected (param i64 i64) (result i32)))
          (import "benchmark" "emit_character" (func $emit (param i32)))
          (func (export "main"))
          (func (export "bench") (param i64) (result i64)
            (if (i32.ne (call $expected (i64.const 0) (i64.const 2)) (i32.const 51)) (then unreachable))
            (i64.const 1))
          (func (export "observe") {emit}))'''
        self.run_wasm_probe(target, 'integer', dict(name='pi', count=2, inputs=[7, 50, 50], expected=['123'], output=output), text)

    def test_clean_native_scalar_float_and_decimal_entries_execute(self):
        for kind in ('scalar', 'floating', 'integer'):
            with self.subTest(kind=kind):
                target = self.probe_directory('native-' + kind)
                source = target / 'case'
                source.mkdir()
                spec = dict(name='fibfp' if kind == 'floating' else 'probe', count=2, inputs=[7], expected=2.5 if kind == 'floating' else [3, 4])
                if kind == 'integer':
                    spec.update(inputs=[7, 50, 50], expected=['123'], output='(123)\n')
                    (target / 'native-input.txt').write_text('2 7 50 50 1\n123\n')
                runner.save(source / 'spec.json', spec)
                provider = clean_native_sources(self.directory, dict(host='integer' if kind == 'integer' else 'scalar'), source, target)
                result_type = 'double' if kind == 'floating' else 'int64_t'
                predicate = 'assert(input_i64(0) == 7); assert(expected_character(0,2) == 51);' if kind == 'integer' else 'assert(input_i64(0) == 7);'
                counter = 'barrier_count' if kind == 'integer' else 'benchmark_barriers'
                counter_type = 'uint64_t' if kind == 'integer' else 'int64_t'
                predicate += f' assert(hide_i64(7) == 7); assert({counter}() == 0);'
                if kind == 'floating':
                    predicate += ' assert(hide_f64(2.5) == 2.5);'
                result = '1' if kind == 'integer' else 'expected_result'
                stub = f'''#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include "{provider}-provider.h"
extern {counter_type} {counter}(void);
void native_host_init(int argc, char **argv) {{ (void)argc; (void)argv; }}
void native_module_init(void) {{}}
int native_finish(int status) {{ return status; }}
void guest_main(void) __asm__("wasm.main");
void guest_main(void) {{}}
{result_type} guest_bench(int64_t n) __asm__("wasm.bench");
{result_type} guest_bench(int64_t n) {{ assert(n == 2); {predicate} return getenv("TIMING_PROBE_WRONG") ? 0 : {result}; }}
void guest_observe(void) __asm__("wasm.observe");
void guest_observe(void) {{ fputs("(123)\\n", stdout); }}
'''
                (target / 'guest.c').write_text(stub)
                built = self.record_probe(target, 'compile', [shutil.which('clang'), '-std=c11', '-I', target,
                                          target / (provider + '-timing-entry.c'), target / (provider + '-provider.c'),
                                          target / 'guest.c', '-o', target / 'program.native'])
                self.assertTrue(runner.succeeded(built), built)
                command = [target / 'program.native', *([target / 'native-input.txt'] if kind == 'integer' else [])]
                executed = self.record_probe(target, 'execute', command)
                self.assertTrue(runner.succeeded(executed), executed)
                self.assertGreater(elapsed_seconds('sfir-native', executed['stdout'], spec), 0)
                failed = runner.record(target, 'wrong-result', command, dict(self.environment, TIMING_PROBE_WRONG='1'), target, 30)
                self.assertFalse(runner.succeeded(failed))
                self.assertNotIn('seconds', failed['stdout'])

    def test_untimed_decimal_chez_control_gets_only_a_driver_adapter(self):
        target = self.probe_directory('decimal-chez')
        source = self.directory / 'source/benchmarks/sfir/pi'
        source.mkdir()
        control = source / 'chez-original.scm'
        control.write_text('''(import (chezscheme))
(define (run-r7rs-benchmark name count thunk correct?) (error 'untimed "original driver"))
(define (run-benchmark) (run-r7rs-benchmark "pi:2" 2 (lambda () '(123)) (lambda (x) (equal? x '(123)))))
(run-benchmark)
''')
        original = runner.digest(control)
        manifest = dict(tools={'CHEZ': dict(path=shutil.which('scheme'))}, config=dict(compile_timeout=30))
        clean_chez_artifact(self.directory, dict(name='pi', host='integer'), 'chez-original', target, manifest, self.environment)
        result = self.record_probe(target, 'execute', [shutil.which('scheme'), '--program', target / 'chez-original.so'])
        self.assertTrue(runner.succeeded(result), result)
        spec = dict(name='pi', count=2, expected=['123'], output='(123)\n')
        self.assertGreater(elapsed_seconds('chez-original', result['stdout'], spec), 0)
        self.assertEqual(runner.digest(control), original)

    def test_clean_attempt_copies_required_fixtures_and_applies_native_heap(self):
        target = self.probe_directory('attempt-fixtures')
        source = self.directory / 'source/benchmarks/sfir/fixture-probe'
        source.mkdir()
        runner.save(source / 'spec.json', dict(name='fixture-probe', count=1, expected=1, execution_files=['probes.scm']))
        (source / 'probes.scm').write_text('required fixture')
        (target / 'input.txt').write_text('canonical input')
        code = 'import os,pathlib; assert pathlib.Path("probes.scm").read_text()=="required fixture"; assert os.environ["SNAIL_GC_HEAP_BYTES"]=="1234"; print(\'{"result":"1","seconds":0.1}\')'
        row = dict(case='fixture-probe', route='sfir-native', command=[sys.executable, '-c', code], execution_environment={'SNAIL_GC_HEAP_BYTES': '1234'})
        manifest = dict(tools={'TASKSET': dict(path=shutil.which('taskset'))}, timing_protocol=dict(cpu=min(os.sched_getaffinity(0))), config=dict(run_timeout=30))
        result = execute_attempt(self.directory, row, target, manifest, self.environment)
        self.assertEqual(result['status'], 'passed', result)


if __name__ == '__main__':
    main()
