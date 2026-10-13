#!/usr/bin/env python3
"""Compare frozen strict/original array1 with the same kernel text on Chez."""

import argparse
from datetime import datetime, timezone
import hashlib
import math
import os
from pathlib import Path
import shutil
import statistics

import measure

DIRECTORY = 'same-source-chez'
SYSTEMS = ('strict', 'chez-original', 'chez-adapted')
SPECIFICATION = dict(name='array1', count=1, inputs=[500, 1000000],
                     expected=1000000, barriers_per_iteration=2)


# ---- Exactly three source edits, with the original Chez harness ----


def kernel_text(source, end):
    start = '(define (create-x n)'
    if source.count(start) != 1 or source.count(end) != 1:
        raise ValueError('array1 kernel boundaries must be unique')
    return source[source.index(start):source.index(end)]


def adapted_source(original, strict):
    kernel = kernel_text(original, '(define (run-benchmark)')
    adapted = measure.array1_kernel(kernel)
    if adapted.strip() != kernel_text(strict, '(define input0 ').strip():
        raise ValueError('adapted Chez kernel differs from strict kernel')
    source = original.replace(kernel, adapted, 1)
    restored = source.replace('(make-vector n 0)', '(make-vector n)').replace('(result 0)', "(result '())")
    if restored != original:
        raise ValueError('Chez source changed outside the three authorized edits')
    return source


def checked_runtime(output, prepared):
    if os.environ.get('NODE_OPTIONS'):
        raise ValueError('NODE_OPTIONS must be unset')
    for tool in prepared['tools'].values():
        if measure.digest(tool['path']) != tool['sha256']:
            raise ValueError('recorded tool changed')
    if measure.digest(output / 'host.mjs') != prepared['host_sha256']:
        raise ValueError('host changed')
    if measure.digest(measure.__file__) != prepared['driver_sha256']:
        raise ValueError('baseline driver changed')


def checked_baseline(output):
    prepared = measure.load(output / 'prepared.json')
    checked_runtime(output, prepared)
    case = next(item for item in prepared['cases'] if item['name'] == 'array1')
    if case['status'] != 'ready' or case['spec'] != SPECIFICATION:
        raise ValueError('original array1 workload changed')
    measure.checked_case(case, output)
    return prepared, case


def prepare(output):
    prepared, case = checked_baseline(output)
    directory = output / DIRECTORY
    directory.mkdir(exist_ok=False)
    original = (output / 'array1/program.scm').read_text()
    strict = (output / 'array1/strict.scm').read_text()
    source = adapted_source(original, strict)
    (directory / 'program.scm').write_text(source)
    shutil.copyfile(__file__, directory / 'driver.py')
    build_control(directory, prepared['tools'])
    validate_control(directory, prepared['tools'])
    freeze_control(output, directory, case, source)


def build_control(directory, tools):
    os.environ['CHEZ'] = tools['CHEZ']['path']
    build, _ = measure.upstream_runner().chez_commands(directory, str(directory / 'program.scm'))
    record = measure.execute(build, directory, os.environ)
    measure.save(directory / 'build.json', record)
    measure.require_success(record)


def validate_control(directory, tools):
    command = [tools['CHEZ']['path'], '--program', directory / 'program.so']
    record = measure.execute(command, directory, os.environ, stdin='3\n7\n7\n')
    measure.save(directory / 'validation.json', dict(record, stdin='3\n7\n7\n'))
    measure.require_success(record)
    parsed = measure.upstream_runner().parse_result(record['stdout'], 'chez', 'array1')
    if record['stderr'] or parsed['status'] != 'ok':
        raise ValueError('adapted Chez behavior check failed')


def freeze_control(output, directory, case, source):
    kernel = kernel_text(source, '(define (run-benchmark)').strip()
    record = dict(date=datetime.now(timezone.utc).isoformat(), specification=case['spec'],
                  baseline_prepared_sha256=measure.digest(output / 'prepared.json'),
                  driver_sha256=measure.digest(__file__), kernel_exact_match=True,
                  complete_source_only_three_authorized_edits=True,
                  kernel_sha256=hashlib.sha256(kernel.encode()).hexdigest(),
                  hashes={path.name: measure.digest(path) for path in directory.iterdir() if path.is_file()})
    measure.save(directory / 'prepared.json', record)


# ---- One discarded full trio and three rotating retained trios ----


def checked_control(output):
    directory = output / DIRECTORY
    control = measure.load(directory / 'prepared.json')
    if measure.digest(__file__) != control['driver_sha256']:
        raise ValueError('control driver changed')
    if measure.digest(output / 'prepared.json') != control['baseline_prepared_sha256']:
        raise ValueError('baseline preparation changed')
    for name, expected in control['hashes'].items():
        if measure.digest(directory / name) != expected:
            raise ValueError(f'control artifact changed: {name}')
    return control


def run_adapted(output, cpu, tools):
    directory = output / DIRECTORY
    command = ['taskset', '-c', str(cpu), tools['CHEZ']['path'], '--program', directory / 'program.so']
    record = measure.execute(command, directory, os.environ, stdin=(output / 'array1/input.txt').read_text())
    if record.get('returncode') != 0 or record.get('stderr'):
        return dict(record, valid=False)
    try:
        parsed = measure.upstream_runner().parse_result(record['stdout'], 'chez', 'array1')
        seconds = parsed['seconds']
        return dict(record, valid=parsed['status'] == 'ok' and math.isfinite(seconds) and seconds > 0,
                    workload_seconds=seconds, checked_result=parsed)
    except (KeyError, ValueError) as error:
        return dict(record, valid=False, validation_error=str(error))


def sample(system, output, cpu):
    prepared, case = checked_baseline(output)
    checked_control(output)
    if system == 'chez-adapted':
        return run_adapted(output, cpu, prepared['tools'])
    return measure.run_case(case, 'strict' if system == 'strict' else 'chez', output, cpu, prepared['tools'])


def run(output, cpu):
    prepared, _ = checked_baseline(output)
    control = checked_control(output)
    report = dict(cpu=cpu, baseline=prepared, control=control, samples=[], complete=False)
    for number in range(-1, 3):
        offset = (number + 1) % len(SYSTEMS)
        for system in SYSTEMS[offset:] + SYSTEMS[:offset]:
            result = sample(system, output, cpu)
            report['samples'].append(dict(result, system=system, round=number, retained=number >= 0))
            measure.save(output / DIRECTORY / 'results.json', report)
            if not result['valid']:
                raise RuntimeError(str(result))
            print(number, system, result['workload_seconds'], flush=True)
    summarize(report)
    report['complete'] = True
    measure.save(output / DIRECTORY / 'results.json', report)


def summarize(report):
    retained = {system: [sample['workload_seconds'] for sample in report['samples']
                        if sample['system'] == system and sample['retained']] for system in SYSTEMS}
    report['medians'] = {system: statistics.median(times) for system, times in retained.items()}
    report['ranges'] = {system: [min(times), max(times)] for system, times in retained.items()}
    report['ratios'] = {system: report['medians']['strict'] / report['medians'][system]
                       for system in ('chez-original', 'chez-adapted')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare', 'measure'))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cpu', type=int, default=5)
    options = parser.parse_args()
    output = options.output.resolve()
    if options.action == 'prepare':
        prepare(output)
    else:
        run(output, options.cpu)


if __name__ == '__main__':
    main()
