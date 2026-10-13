#!/usr/bin/env python3
"""Compare the frozen F64 kernels with Chez using explicit flonum operations."""

import argparse
from datetime import datetime, timezone
import difflib
import math
import os
from pathlib import Path
import re
import shutil
import statistics

import measure

SUPPORTED = ('fibfp', 'sumfp', 'mbrot', 'pnpoly')
REGIONS = dict(fibfp=('(define (fibfp ', '(define (run-benchmark)'),
               sumfp=('(define (run n)', '(define (run-benchmark)'),
               mbrot=('(define (count r i step x y)', '(define (mbrot matrix'),
               pnpoly=('(define (pt-in-poly2 xp yp x y)', '(define (run input1'))
OPERATORS = dict(fibfp={'+': 'fl+', '-': 'fl-', '<': 'fl<?'},
                 sumfp={'+': 'fl+', '-': 'fl-', '<': 'fl<?'},
                 mbrot={'+': 'fl+', '-': 'fl-', '*': 'fl*', '>': 'fl>?'},
                 pnpoly={'+': 'fl+', '-': 'fl-', '*': 'fl*', '/': 'fl/',
                         '>': 'fl>?', '>=': 'fl>=?'})
INTEGER_FORMS = dict(fibfp=[], sumfp=[], mbrot=[('(+ c 1)', '(fl+ c 1)', 1)],
                     pnpoly=[('(- (vector-length xp) 1)', '(fl- (vector-length xp) 1)', 1),
                             ('(- i 1)', '(fl- i 1)', 2)])
FLOAT_COUNTS = dict(mbrot={'+': 5, '-': 1, '*': 6, '>': 1},
                    pnpoly={'+': 1, '-': 3, '*': 1, '/': 1, '>': 2, '>=': 3})


# ---- Change only the original Chez kernel's arithmetic ----


def checked_baseline(output):
    prepared = measure.load(output / 'prepared.json')
    if os.environ.get('NODE_OPTIONS'):
        raise ValueError('NODE_OPTIONS must be unset')
    for tool in prepared['tools'].values():
        if measure.digest(tool['path']) != tool['sha256']:
            raise ValueError('recorded tool changed')
    if measure.digest(output / 'host.mjs') != prepared['host_sha256']:
        raise ValueError('host changed')
    return prepared


def selected_cases(prepared, names):
    cases = [case for case in prepared['cases'] if case['status'] == 'ready' and case['name'] in SUPPORTED]
    if names:
        cases = [case for case in cases if case['name'] in names]
        if {case['name'] for case in cases} != set(names) or len(names) != len(set(names)):
            raise ValueError('selected controls must be unique ready supported baseline cases')
    if not cases:
        raise ValueError('no supported ready cases')
    return cases


def prepare(output, names=None):
    prepared = checked_baseline(output)
    cases = selected_cases(prepared, names)
    runner = measure.upstream_runner()
    tools = {name: item['path'] for name, item in prepared['tools'].items()}
    os.environ['CHEZ'] = tools['CHEZ']
    directory = output / 'flonum-controls'
    directory.mkdir(exist_ok=False)
    shutil.copyfile(__file__, directory / 'driver.py')
    report = preparation_record(output, cases)
    measure.save(directory / 'prepared.json', report)
    for case in cases:
        try:
            control = dict(prepare_case(case, output, tools, runner), status='ready')
        except (RuntimeError, ValueError, OSError) as error:
            control = dict(name=case['name'], status='prepare-failed', diagnostic=str(error))
        report['cases'].append(control)
        measure.save(directory / 'prepared.json', report)
        print(control['status'], case['name'], flush=True)
    report['complete'] = all(item['status'] == 'ready' for item in report['cases'])
    measure.save(directory / 'prepared.json', report)


def preparation_record(output, cases):
    return dict(date=datetime.now(timezone.utc).isoformat(), cases=[], complete=False,
                expected_cases=[case['name'] for case in cases],
                baseline_prepared_sha256=measure.digest(output / 'prepared.json'),
                control_driver_sha256=measure.digest(__file__), measure_driver_sha256=measure.digest(measure.__file__),
                runner_sha256=measure.digest(measure.ROOT / 'benchmarks/r7rs.py'))


def floating_region(name, source):
    start, end = REGIONS[name]
    if source.count(start) != 1 or source.count(end) != 1:
        raise ValueError('floating function boundaries must be unique')
    first, last = source.index(start), source.index(end)
    if first >= last:
        raise ValueError('floating function boundaries are out of order')
    return first, last, source[first:last]


def floating_kernel(name, kernel):
    for form, converted, count in INTEGER_FORMS[name]:
        if kernel.count(form) != count:
            raise ValueError('protected integer arithmetic changed')
    changed = kernel
    for operation, native in OPERATORS[name].items():
        changed = re.sub(r'\(' + re.escape(operation) + r'(?=\s)', '(' + native, changed)
    for form, converted, count in INTEGER_FORMS[name]:
        changed = measure.replace_exact(changed, converted, form, count)
    validate_float_edits(name, kernel, changed)
    return changed


def validate_float_edits(name, original, changed):
    restored = changed
    for operation, native in OPERATORS[name].items():
        restored = re.sub(r'\(' + re.escape(native) + r'(?=\s)', '(' + operation, restored)
        count = len(re.findall(r'\(' + re.escape(native) + r'(?=\s)', changed))
        if name in FLOAT_COUNTS and count != FLOAT_COUNTS[name][operation]:
            raise ValueError('unexpected floating replacement count')
    if restored != original:
        raise ValueError('reversing floating operators did not restore the original function')
    for form, converted, count in INTEGER_FORMS[name]:
        if changed.count(form) != count:
            raise ValueError('integer arithmetic did not survive the control')


def control_source(name, original):
    first, last, kernel = floating_region(name, original)
    changed = floating_kernel(name, kernel)
    source = original[:first] + changed + original[last:]
    if source[:first] != original[:first] or source[first + len(changed):] != original[last:]:
        raise ValueError('control changed code outside its floating function')
    return source


def prepare_case(baseline, output, tools, runner):
    name = baseline['name']
    original_directory = measure.checked_case(baseline, output)
    directory = output / 'flonum-controls' / name
    directory.mkdir()
    relative = write_control_source(name, original_directory, directory)
    build, command = runner.chez_commands(directory, str(directory / 'program.scm'))
    record = measure.execute(build, directory, os.environ)
    measure.save(directory / 'build.json', record)
    measure.require_success(record)
    validate_control(name, command, directory, original_directory, runner)
    return case_record(name, directory, original_directory, relative)


def write_control_source(name, original_directory, directory):
    relative = 'same-source-chez/program.scm' if name in ('mbrot', 'pnpoly') else 'program.scm'
    original = (original_directory / relative).read_text()
    changed = control_source(name, original)
    (directory / 'program.scm').write_text(changed)
    patch = difflib.unified_diff(original.splitlines(True), changed.splitlines(True),
                                 fromfile=relative, tofile='flonum-control/program.scm')
    (directory / 'arithmetic.patch').write_text(''.join(patch))
    measure.save(directory / 'source-proof.json', source_proof(name, original, changed))
    return relative


def source_proof(name, original, changed):
    first, last, kernel = floating_region(name, original)
    _, _, control = floating_region(name, changed)
    return dict(function_start=REGIONS[name][0], function_end=REGIONS[name][1],
                unchanged_outside_function=changed[:first] == original[:first] and changed[first + len(control):] == original[last:],
                exact_operator_reversal=True,
                floating_sites={native: len(re.findall(r'\(' + re.escape(native) + r'(?=\s)', control))
                                for native in OPERATORS[name].values()},
                protected_integer_forms={form: control.count(form) for form, converted, count in INTEGER_FORMS[name]},
                premise='Arithmetic domains are audited for these pinned functions; counts and reversal prove textual preservation, not type inference.')


def case_record(name, directory, original_directory, relative):
    return dict(name=name, artifact_sha256=measure.digest(directory / 'program.so'),
                source_sha256=measure.digest(directory / 'program.scm'),
                input_sha256=measure.digest(original_directory / 'input.txt'),
                baseline_source=relative, baseline_source_sha256=measure.digest(original_directory / relative),
                strict_artifact_sha256=measure.digest(original_directory / 'strict.wasm'),
                hashes={p.name: measure.digest(p) for p in directory.iterdir() if p.is_file()})


def validate_control(name, command, directory, original_directory, runner):
    records = []
    for count in (1, 2):
        data = runner.input_data((original_directory / 'input.txt').read_bytes(), count).decode()
        record = measure.execute(command, directory, os.environ, stdin=data)
        records.append(dict(record, count=count, stdin=data))
        measure.save(directory / 'validation.json', records)
        measure.require_success(record)
        parsed = runner.parse_result(record['stdout'], 'chez', name)
        if record['stderr'] or parsed['status'] != 'ok' or not math.isfinite(parsed['seconds']) or parsed['seconds'] <= 0:
            raise ValueError('flonum control returned an invalid result or duration')


# ---- Fresh balanced pairs with the same strict artifacts ----


def run_chez(case, output, cpu, tools):
    directory = output / 'flonum-controls' / case['name']
    command = ['taskset', '-c', str(cpu), tools['CHEZ']['path'], '--program', directory / 'program.so']
    data = (output / case['name'] / 'input.txt').read_text()
    record = measure.execute(command, directory, os.environ, stdin=data)
    if record.get('returncode') != 0 or record.get('stderr'):
        return dict(record, valid=False)
    try:
        parsed = measure.upstream_runner().parse_result(record['stdout'], 'chez', case['name'])
        seconds = parsed['seconds']
        return dict(record, valid=parsed['status'] == 'ok' and math.isfinite(seconds) and seconds > 0,
                    workload_seconds=seconds, checked_result=parsed)
    except (KeyError, ValueError) as error:
        return dict(record, valid=False, validation_error=str(error))


def checked_controls(output):
    controls = measure.load(output / 'flonum-controls/prepared.json')
    if isinstance(controls, list):
        return controls  # Historical archives retain their recorded source/artifact hashes.
    if not controls['complete']:
        raise ValueError('control preparation is incomplete or has recorded failures')
    if [case['name'] for case in controls['cases']] != controls['expected_cases']:
        raise ValueError('control preparation does not contain every selected case')
    if any(case['status'] != 'ready' for case in controls['cases']):
        raise ValueError('control preparation has recorded failures')
    for path, key in ((Path(__file__), 'control_driver_sha256'), (Path(measure.__file__), 'measure_driver_sha256'),
                      (measure.ROOT / 'benchmarks/r7rs.py', 'runner_sha256'),
                      (output / 'prepared.json', 'baseline_prepared_sha256')):
        if measure.digest(path) != controls[key]:
            raise ValueError('frozen control dependency changed: ' + str(path))
    return controls['cases']


def checked_control_case(case, output):
    directory = output / 'flonum-controls' / case['name']
    hashes = case.get('hashes', {'program.scm': case['source_sha256'], 'program.so': case['artifact_sha256']})
    for name, expected in hashes.items():
        if measure.digest(directory / name) != expected:
            raise ValueError('flonum control file changed: ' + name)
    if 'input_sha256' in case and measure.digest(output / case['name'] / 'input.txt') != case['input_sha256']:
        raise ValueError('original control inputs changed')
    if 'baseline_source_sha256' in case and measure.digest(output / case['name'] / case['baseline_source']) != case['baseline_source_sha256']:
        raise ValueError('source-matched baseline changed')


def sample(case, system, output, cpu, prepared):
    checked_baseline(output)
    checked_controls(output)
    checked_control_case(case, output)
    original = next(item for item in prepared['cases'] if item['name'] == case['name'])
    directory = measure.checked_case(original, output)
    if 'strict_artifact_sha256' in case and measure.digest(directory / 'strict.wasm') != case['strict_artifact_sha256']:
        raise ValueError('strict comparison artifact changed')
    if system == 'chez-flonum':
        return run_chez(case, output, cpu, prepared['tools'])
    return measure.run_case(original, 'strict', output, cpu, prepared['tools'])


def run(output, cpu):
    prepared = checked_baseline(output)
    cases = checked_controls(output)
    report = dict(cpu=cpu, cases=cases, samples=[], complete=False,
                  baseline_prepared_sha256=measure.digest(output / 'prepared.json'),
                  control_prepared_sha256=measure.digest(output / 'flonum-controls/prepared.json'))
    for number in range(-1, 3):
        for case in (cases if number % 2 else cases[::-1]):
            order = ('strict', 'chez-flonum') if (number + cases.index(case)) % 2 else ('chez-flonum', 'strict')
            for system in order:
                try:
                    result = sample(case, system, output, cpu, prepared)
                except (RuntimeError, ValueError, OSError) as error:
                    result = dict(valid=False, preflight_error=str(error))
                report['samples'].append(dict(result, name=case['name'], system=system,
                                              round=number, retained=number >= 0))
                measure.save(output / 'flonum-controls/results.json', report)
                if not result['valid']:
                    raise RuntimeError(str(result))
                print(number, case['name'], system, result['workload_seconds'], flush=True)
    summarize(report)
    report['complete'] = True
    measure.save(output / 'flonum-controls/results.json', report)


def summarize(report):
    report['medians'], report['ranges'] = {}, {}
    for case in report['cases']:
        medians, ranges = {}, {}
        for system in ('strict', 'chez-flonum'):
            times = [s['workload_seconds'] for s in report['samples']
                     if s['name'] == case['name'] and s['system'] == system and s['retained']]
            medians[system], ranges[system] = statistics.median(times), [min(times), max(times)]
        report['medians'][case['name']], report['ranges'][case['name']] = medians, ranges


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare', 'measure'))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cpu', type=int, default=5)
    parser.add_argument('--benchmarks', nargs='+', choices=SUPPORTED)
    options = parser.parse_args()
    if options.action == 'measure' and options.benchmarks:
        parser.error('choose cases during preparation; measurement uses frozen controls')
    if options.action == 'prepare':
        prepare(options.output.resolve(), options.benchmarks)
    else:
        run(options.output.resolve(), options.cpu)


if __name__ == '__main__':
    main()
