#!/usr/bin/env python3
"""Compare the frozen F64 kernels with Chez using explicit flonum operations."""

import argparse
import os
from pathlib import Path
import statistics

import measure


# ---- Change only the original Chez kernel's arithmetic ----


def prepare(output):
    prepared = measure.load(output / 'prepared.json')
    runner = measure.upstream_runner()
    tools = {name: item['path'] for name, item in prepared['tools'].items()}
    os.environ['CHEZ'] = tools['CHEZ']
    directory = output / 'flonum-controls'
    directory.mkdir(exist_ok=False)
    records = []
    for name in measure.FLOATS:
        records.append(prepare_case(name, output, tools, runner))
        measure.save(directory / 'prepared.json', records)


def prepare_case(name, output, tools, runner):
    directory = output / 'flonum-controls' / name
    directory.mkdir()
    original = (output / name / 'program.scm').read_text()
    start = original.index('(define (fibfp ' if name == 'fibfp' else '(define (run n)')
    end = original.index('(define (run-benchmark)', start)
    kernel = original[start:end]
    for operation, native in (('+', 'fl+'), ('-', 'fl-'), ('<', 'fl<?')):
        kernel = kernel.replace('(' + operation + ' ', '(' + native + ' ')
    (directory / 'program.scm').write_text(original[:start] + kernel + original[end:])
    build, command = runner.chez_commands(directory, str(directory / 'program.scm'))
    record = measure.execute(build, directory, os.environ)
    measure.save(directory / 'build.json', record)
    measure.require_success(record)
    data = runner.input_data((output / name / 'input.txt').read_bytes(), 1).decode()
    record = measure.execute(command, directory, os.environ, stdin=data)
    measure.save(directory / 'validation.json', record)
    measure.require_success(record)
    if runner.parse_result(record['stdout'], 'chez', name)['status'] != 'ok':
        raise ValueError('flonum control returned an incorrect answer')
    return dict(name=name, artifact_sha256=measure.digest(directory / 'program.so'),
                source_sha256=measure.digest(directory / 'program.scm'))


# ---- Fresh balanced pairs with the same strict artifacts ----


def run_chez(case, output, cpu, tools):
    directory = output / 'flonum-controls' / case['name']
    if measure.digest(directory / 'program.so') != case['artifact_sha256']:
        raise ValueError('Chez flonum artifact changed')
    command = ['taskset', '-c', str(cpu), tools['CHEZ']['path'], '--program', directory / 'program.so']
    data = (output / case['name'] / 'input.txt').read_text()
    record = measure.execute(command, directory, os.environ, stdin=data)
    if record.get('returncode') != 0 or record.get('stderr'):
        return dict(record, valid=False)
    parsed = measure.upstream_runner().parse_result(record['stdout'], 'chez', case['name'])
    return dict(record, valid=parsed['status'] == 'ok', workload_seconds=parsed.get('seconds'))


def sample(case, system, output, cpu, prepared):
    if system == 'chez-flonum':
        return run_chez(case, output, cpu, prepared['tools'])
    original = next(item for item in prepared['cases'] if item['name'] == case['name'])
    return measure.run_case(original, 'strict', output, cpu, prepared['tools'])


def run(output, cpu):
    prepared = measure.load(output / 'prepared.json')
    if os.environ.get('NODE_OPTIONS'):
        raise ValueError('NODE_OPTIONS must be unset')
    for item in prepared['tools'].values():
        if measure.digest(item['path']) != item['sha256']:
            raise ValueError('tool changed')
    if measure.digest(output / 'host.mjs') != prepared['host_sha256']:
        raise ValueError('host changed')
    cases = measure.load(output / 'flonum-controls/prepared.json')
    report = dict(cpu=cpu, cases=cases, samples=[], complete=False)
    for number in range(-1, 3):
        for case in (cases if number % 2 else cases[::-1]):
            order = ('strict', 'chez-flonum') if (number + cases.index(case)) % 2 else ('chez-flonum', 'strict')
            for system in order:
                result = sample(case, system, output, cpu, prepared)
                report['samples'].append(dict(result, name=case['name'], system=system,
                                              round=number, retained=number >= 0))
                measure.save(output / 'flonum-controls/results.json', report)
                if not result['valid']:
                    raise RuntimeError(str(result))
                print(number, case['name'], system, result['workload_seconds'], flush=True)
    report['medians'] = {name: {system: statistics.median(s['workload_seconds'] for s in report['samples']
                         if s['name'] == name and s['system'] == system and s['retained'])
                         for system in ('strict', 'chez-flonum')} for name in measure.FLOATS}
    report['complete'] = True
    measure.save(output / 'flonum-controls/results.json', report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare', 'measure'))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cpu', type=int, default=5)
    options = parser.parse_args()
    if options.action == 'prepare':
        prepare(options.output.resolve())
    else:
        run(options.output.resolve(), options.cpu)


if __name__ == '__main__':
    main()
