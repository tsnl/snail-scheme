#!/usr/bin/env python3
"""Measure original-sized R7RS kernels expressed in the strict Scheme subset."""

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
NAMES = ('ack', 'tak', 'cpstak', 'fib', 'fibfp', 'sum', 'sumfp',
         'takl', 'ntakl', 'diviter', 'divrec', 'array1')
FLOATS = ('fibfp', 'sumfp')
LISTS = ('takl', 'ntakl', 'diviter', 'divrec')
KERNELS = dict(ack='ack', tak='tak', cpstak='cpstak', fib='fib', fibfp='fibfp',
               sum='run', sumfp='run', takl='mas', ntakl='mas',
               diviter='iterative-div2', divrec='recursive-div2', array1='go')


# ---- Fixed inputs and mechanical source adaptation ----


def load(path):
    return json.loads(Path(path).read_text())


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def upstream_runner():
    spec = importlib.util.spec_from_file_location('r7rs', ROOT / 'benchmarks/r7rs.py')
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    return runner


def input_values(text):
    tokens = iter(re.findall(r'\(|\)|[^\s()]+', re.sub(r';[^\n]*', '', text)))

    def datum(token):
        if token == '(':
            values = []
            for item in tokens:
                if item == ')':
                    return values
                values.append(datum(item))
            raise ValueError('unclosed input list')
        return float(token) if re.search(r'[.eE]', token) else int(token)

    return [datum(token) for token in tokens]


def case_specification(name, data):
    values = input_values(data.decode())
    if name == 'array1':
        repeats, size, expected = values
        return dict(name=name, count=1, inputs=[repeats, size], expected=expected,
                    barriers_per_iteration=2)
    arity = 3 if name in ('tak', 'cpstak', 'takl', 'ntakl') else 2 if name == 'ack' else 1
    count, *rest = values
    inputs, expected = rest[:arity], rest[arity]
    if name in ('takl', 'ntakl'):
        assert all(xs == list(range(len(xs), 0, -1)) for xs in inputs)
        inputs = list(map(len, inputs))
    barriers = 0 if name in ('diviter', 'divrec') else arity
    return dict(name=name, count=count, inputs=inputs, expected=expected,
                barriers_per_iteration=barriers)


PRELUDE = '''(import (snail strict))
(define-syntax cond
  (syntax-rules (else)
    ((_ (else body ...)) (begin body ...))
    ((_ (test body ...) rest ...) (if test (begin body ...) (cond rest ...)))))
(define-syntax do
  (syntax-rules ()
    ((_ ((var init step) ...) (test result) body ...)
     (let loop ((var init) ...)
       (if test result (begin body ... (loop step ...)))))))
(define (cddr xs) (cdr (cdr xs)))
(define (length xs)
  (let loop ((xs xs) (n 0)) (if (null? xs) n (loop (cdr xs) (+ n 1)))))
(define-extern native-input-i64 "benchmark" "input_i64" (-> I32 I64))
(define-extern native-input-f64 "benchmark" "input_f64" (-> I32 F64))
(define-extern barrier "benchmark" "barrier" (-> Bool))
(define-extern hide-i64 "benchmark" "hide_i64" (-> I64 I64))
(define-extern hide-f64 "benchmark" "hide_f64" (-> F64 F64))
'''


def kernel_source(name, source):
    source = source[:source.index('(define (run-benchmark)')]
    source = re.sub(r'^\(import [^\n]*\)\s*$', '', source, flags=re.M)
    if name in FLOATS:
        for operation, native in (('+', 'f64-add'), ('-', 'f64-sub'), ('<', 'f64-lt')):
            source = source.replace('(' + operation + ' ', '(' + native + ' ')
    if name in ('diviter', 'divrec'):
        source = '(: create-n (-> I64 (List (List Never))))\n' + source
    if name == 'array1':
        source = array1_kernel(source)
    return source


def array1_kernel(source):
    # Both fill loops overwrite every element before reading it. The original
    # empty-list initial result is unreachable at its positive repeat count.
    assert source.count('(make-vector n)') == 2
    assert source.count("(result '())") == 1
    return source.replace('(make-vector n)', '(make-vector n 0)').replace("(result '())", '(result 0)')


def input_bindings(name, spec):
    bindings = []
    for index in range(len(spec['inputs'])):
        value = f'(native-input-{"f64" if name in FLOATS else "i64"} (ann {index} I32))'
        if name in ('takl', 'ntakl'):
            value = f'(listn {value})'
        elif name in ('diviter', 'divrec'):
            value = f'(create-n {value})'
        bindings.append(f'(define input{index} {value})')
    return '\n'.join(bindings)


def strict_program(name, spec, upstream):
    arguments = [f'input{i}' for i in range(len(spec['inputs']))]
    if spec['barriers_per_iteration']:
        opacity_count = 'input0' if name == 'array1' else 'count'
        arguments = [f'(hide {opacity_count} {value})' for value in arguments]
    call = f'({KERNELS[name]} {" ".join(arguments)})'
    initial = "'()" if name in LISTS else '0.0' if name in FLOATS else '0'
    result = 'F64' if name in FLOATS else 'I64'
    loop = f'''(let loop ((i 0) (result {initial}))
    (if (< i count) (loop (+ i 1) {call}) result))'''
    if name in LISTS:
        loop = f'(length {loop})'
    worker = f'(: bench (-> I64 {result}))\n(define (bench count) {loop})\n(unit)\n'
    hide = '(if (barrier) x (unreachable))' if name in LISTS else f'(hide-{"f64" if name in FLOATS else "i64"} x)'
    return (PRELUDE + f'(define (hide count x) {hide})\n' + kernel_source(name, upstream)
            + input_bindings(name, spec) + '\n' + worker)


# ---- Preparation: freeze sources, build and validate before timing ----


def execute(command, cwd, environment, timeout=300, stdin=None):
    started = time.perf_counter()
    try:
        run = subprocess.run(list(map(str, command)), cwd=cwd, env=environment,
                             input=stdin, capture_output=True, text=True, timeout=timeout)
        return dict(command=list(map(str, command)), returncode=run.returncode,
                    stdout=run.stdout, stderr=run.stderr, process_seconds=time.perf_counter() - started)
    except (subprocess.TimeoutExpired, OSError, UnicodeError) as error:
        return dict(command=list(map(str, command)), error=str(error),
                    process_seconds=time.perf_counter() - started)


def require_success(record):
    if record.get('returncode') != 0:
        raise RuntimeError(str(record))


def tool_paths():
    names = dict(CHIBI='chibi-scheme', NODE='node', WASM_AS='wasm-as', WASM_OPT='wasm-opt',
                 WASM_DIS='wasm-dis', CHEZ='scheme')
    paths = {key: shutil.which(os.environ.get(key, value)) for key, value in names.items()}
    if not all(paths.values()):
        raise ValueError(f'missing tools: {paths}')
    return paths


def build_strict(directory, tools, environment):
    command = [ROOT / 'scripts/build-strict', '--export', 'bench',
               directory / 'strict.scm', directory / 'strict.wasm']
    record = execute(command, ROOT, environment)
    save(directory / 'strict-build.json', record)
    require_success(record)
    record = execute([tools['WASM_DIS'], directory / 'strict.wasm', '-o',
                      directory / 'strict.optimized.wat'], ROOT, environment)
    require_success(record)


def validate_strict(directory, tools, environment):
    spec = load(directory / 'spec.json')
    checks = []
    for label, probe in validation_specifications(spec):
        save(directory / f'validation-spec-{label}.json', probe)
        for suffix in ('.raw.wasm', ''):
            command = [tools['NODE'], directory.parent / 'host.mjs', directory / ('strict.wasm' + suffix),
                       directory / f'validation-spec-{label}.json', '--validate']
            record = execute(command, directory, environment)
            checks.append(record)
            save(directory / 'validation.json', checks)
            require_success(record)


def validation_specifications(spec):
    if spec['name'] != 'array1':
        return [(str(count), dict(spec, count=count)) for count in (1, 2)]
    # These are behavior probes, not performance samples. The discarded full
    # pair later checks the unchanged original workload on both systems.
    return [(f'{count}-{repeats}-{size}',
             dict(spec, count=count, inputs=[repeats, size], expected=size if repeats else 0))
            for count, repeats, size in ((1, 1, 0), (1, 1, 1), (2, 3, 7), (1, 0, 7))]


def prepare_case(name, files, output, runner, tools, environment):
    directory = output / name
    directory.mkdir()
    spec = case_specification(name, files[f'inputs/{name}.input'])
    save(directory / 'spec.json', spec)
    (directory / 'input.txt').write_bytes(files[f'inputs/{name}.input'])
    (directory / 'upstream.scm').write_bytes(files[f'src/{name}.scm'])
    (directory / 'strict.scm').write_text(strict_program(name, spec, files[f'src/{name}.scm'].decode()))
    (directory / 'program.scm').write_text(runner.source_text(files, name, 'chez'))
    build_strict(directory, tools, environment)
    build, run = runner.chez_commands(directory, str(directory / 'program.scm'))
    record = execute(build, directory, environment)
    save(directory / 'chez-build.json', record)
    require_success(record)
    validate_strict(directory, tools, environment)
    return dict(name=name, status='ready', spec=spec, chez_command=run,
                hashes={p.name: digest(p) for p in directory.iterdir() if p.is_file()})


def prepare(options):
    runner, tools = upstream_runner(), tool_paths()
    environment = {**os.environ, **tools, 'BINARYEN_CORES': '1'}
    files = runner.suite_sources()
    options.output.mkdir(parents=True, exist_ok=False)
    shutil.copy2(HERE / 'host.mjs', options.output / 'host.mjs')
    shutil.copy2(__file__, options.output / 'measure.py')
    sources = [*ROOT.glob('src/**/*.sld'), ROOT / 'scripts/build-strict', ROOT / 'tests/build-strict-program.scm']
    for source in sources:
        target = options.output / 'compiler-source' / source.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    report = dict(date=datetime.now(timezone.utc).isoformat(), cases=[],
                  tools={key: dict(path=value, sha256=digest(value)) for key, value in tools.items()},
                  compiler_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                  compiler_files={str(p.relative_to(ROOT)): digest(p) for p in sources},
                  upstream_commit=runner.REVISION, host_sha256=digest(options.output / 'host.mjs'),
                  driver_sha256=digest(__file__))
    for name in options.benchmarks:
        try:
            case = prepare_case(name, files, options.output, runner, tools, environment)
        except (RuntimeError, ValueError) as error:
            case = dict(name=name, status='prepare-failed', diagnostic=str(error))
        report['cases'].append(case)
        save(options.output / 'prepared.json', report)
        print(case['status'], name, flush=True)
    if report['compiler_files'] != {str(p.relative_to(ROOT)): digest(p) for p in sources}:
        raise ValueError('compiler changed during preparation')


# ---- Clean fresh-process measurements ----


def checked_case(case, output):
    directory = output / case['name']
    for name, expected in case['hashes'].items():
        if digest(directory / name) != expected:
            raise ValueError(f'changed artifact: {directory / name}')
    return directory


def run_case(case, system, output, cpu, tools):
    directory = checked_case(case, output)
    if system == 'strict':
        command = [tools['NODE']['path'], output / 'host.mjs', directory / 'strict.wasm', directory / 'spec.json']
        data = None
    else:
        command = [tools['CHEZ']['path'], '--program', directory / 'program.so']
        data = (directory / 'input.txt').read_text()
    result = execute(['taskset', '-c', str(cpu), *command], directory, os.environ, stdin=data)
    if result.get('returncode') != 0 or result.get('stderr'):
        return dict(result, valid=False)
    try:
        parsed = json.loads(result['stdout']) if system == 'strict' else upstream_runner().parse_result(result['stdout'], 'chez', case['name'])
        seconds = parsed['seconds']
        assert math.isfinite(seconds) and seconds > 0
        return dict(result, valid=True, workload_seconds=seconds, checked_result=parsed)
    except (KeyError, ValueError, AssertionError) as error:
        return dict(result, valid=False, validation_error=str(error))


def measure(options):
    if os.environ.get('NODE_OPTIONS'):
        raise ValueError('NODE_OPTIONS must be unset')
    prepared = load(options.output / 'prepared.json')
    if prepared.get('driver_sha256', digest(__file__)) != digest(__file__):
        raise ValueError('driver changed')
    for record in prepared['tools'].values():
        if digest(record['path']) != record['sha256']:
            raise ValueError('tool changed')
    if digest(options.output / 'host.mjs') != prepared['host_sha256']:
        raise ValueError('host changed')
    report = dict(prepared=prepared, cpu=options.cpu, rounds=options.rounds, samples=[], complete=False)
    for round_number in range(-1, options.rounds):
        cases = [case for case in prepared['cases'] if case['status'] == 'ready']
        if not cases:
            raise ValueError('no ready cases')
        offset = max(round_number, 0) % len(cases)
        for case in cases[offset:] + cases[:offset]:
            index = cases.index(case)
            systems = ('strict', 'chez') if (round_number + index) % 2 else ('chez', 'strict')
            for system in systems:
                sample = run_case(case, system, options.output, options.cpu, prepared['tools'])
                report['samples'].append(dict(sample, name=case['name'], system=system,
                                              round=round_number, retained=round_number >= 0))
                save(options.output / 'results.json', report)
                if not sample['valid']:
                    raise RuntimeError(str(sample))
                print(round_number, case['name'], system, sample['workload_seconds'], flush=True)
    report['medians'] = {name: {system: statistics.median(s['workload_seconds'] for s in report['samples']
                         if s['name'] == name and s['system'] == system and s['retained'])
                         for system in ('strict', 'chez')} for name in [case['name'] for case in cases]}
    report['complete'] = True
    save(options.output / 'results.json', report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare', 'measure'))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--benchmarks', nargs='+', choices=NAMES, default=list(NAMES))
    parser.add_argument('--rounds', type=int, default=3)
    parser.add_argument('--cpu', type=int, default=5)
    options = parser.parse_args()
    options.output = options.output.resolve()
    if options.rounds < 1:
        parser.error('rounds must be positive')
    (prepare if options.action == 'prepare' else measure)(options)


if __name__ == '__main__':
    main()
