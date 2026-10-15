"""Compare concrete SFIR scalar services with numeric and Unicode oracles."""

import json
import math
import os
from pathlib import Path
import signal
import struct
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'build' / f'sfir-scalars-{time.time_ns()}'
VALUES = ['-Infinity', '-1e300', '-1', '-0.5', '-0', '0', '5e-324', '0.5',
          '1', '2', '1e300', 'Infinity', 'NaN']


# ---- Independent expected results preserve nonfinite values and zero signs ----


def round_value(value, ceiling, narrow):
    if narrow:
        try:
            value = struct.unpack('f', struct.pack('f', value))[0]
        except OverflowError:
            return 'trap'
    if not math.isfinite(value) or value == 0.0:
        return value
    result = float(math.ceil(value) if ceiling else math.floor(value))
    return math.copysign(0.0, value) if result == 0 else result


def unary_expected(operation, value):
    if operation >= 5:
        return round_value(value, operation in (6, 8), operation in (7, 8))
    try:
        return (math.exp, math.log, math.tan, math.asin, math.acos)[operation](value)
    except ValueError:
        return -math.inf if operation == 1 and value == 0 else math.nan
    except OverflowError:
        return math.inf


def cases():
    result = [('unary', operation, value, '0', unary_expected(operation, float(value)))
              for operation in range(9) for value in VALUES]
    for left, right in [('-0', '1'), ('0', '-1'), ('-0', '-1'), ('1', '-1'),
                        ('Infinity', 'Infinity'), ('-Infinity', 'Infinity'), ('NaN', '1')]:
        result.append(('binary', 0, left, right, math.atan2(float(left), float(right))))
    for left, right, expected in [('4', '.5', 2), ('-2', '3', -8), ('2', '-3', .125),
                                  ('-1', '.5', math.nan), ('-0', '3', -0.0), ('0', '0', 1)]:
        result.append(('binary', 1, left, right, expected))
    for operation, character, expected in [(0, 'λ', ord('Λ')), (0, 'ß', ord('ß')),
                                           (0, 'ᾀ', ord('ᾈ')), (0, '😀', ord('😀')),
                                           (1, 'ς', ord('σ')), (1, 'ſ', ord('s')),
                                           (1, 'µ', ord('μ')), (1, 'A', ord('a')),
                                           (2, 'λ', 1), (2, 'Λ', 0), (2, '😀', 0)]:
        result.append(('character', operation, str(ord(character)), '0', expected))
    return result


# ---- Every invocation retains its terminal result, including timeouts ----


def run(command, label, expected_error=None):
    command = list(map(str, command))
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, start_new_session=True, env={**os.environ, 'BINARYEN_CORES': '1'})
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=300)
    except subprocess.TimeoutExpired:
        timed_out = True
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate()
    record = dict(command=command, status=process.returncode, stdout=stdout, stderr=stderr, timed_out=timed_out)
    (OUTPUT / (label + '.json')).write_text(json.dumps(record, indent=2) + '\n')
    assert not timed_out, record
    if expected_error is None:
        assert process.returncode == 0 and not stderr, record
    else:
        assert process.returncode == 1 and expected_error in stderr, record
    return stdout


def check_output(output, inputs):
    actual = list(map(float, output.splitlines()))
    assert len(actual) == len(inputs), (len(actual), len(inputs))
    for value, case in zip(actual, inputs):
        target = case[-1]
        if math.isnan(target):
            assert math.isnan(value), (case, value)
        elif target == 0:
            assert value == 0 and math.copysign(1.0, value) == math.copysign(1.0, target), (case, value)
        else:
            assert math.isclose(value, target, rel_tol=3e-15, abs_tol=0), (case, value)


def check_wasm(source, arguments, inputs):
    for suffix, flags, name in [('', [], 'optimized'), ('.raw.wasm', ['--diagnostic-prune-only'], 'raw')]:
        linked = OUTPUT / (name + '.wasm')
        run([ROOT / 'scripts/link-sfir-runtime', *flags, Path(str(source) + suffix), linked], name + '-link')
        result = run([os.environ.get('NODE', 'node'), '--disable-warning=ExperimentalWarning',
                      ROOT / 'tests/sfir/scalar-services.mjs', linked, *arguments], name + '-run')
        check_output(result, inputs)


def check_traps(native, inputs):
    for index, case in enumerate(inputs):
        arguments = list(map(str, case[:-1]))
        for name in ('raw', 'optimized'):
            run([os.environ.get('NODE', 'node'), '--disable-warning=ExperimentalWarning',
                 ROOT / 'tests/sfir/scalar-services.mjs', OUTPUT / (name + '.wasm'), *arguments],
                f'{name}-overflow-{index}', 'RuntimeError: unreachable')
        run([native, *arguments], f'native-overflow-{index}', 'WebAssembly trap\n')


def main():
    OUTPUT.mkdir(parents=True)
    all_inputs = cases()
    inputs = [case for case in all_inputs if case[-1] != 'trap']
    traps = [case for case in all_inputs if case[-1] == 'trap']
    arguments = [str(value) for case in inputs for value in case[:-1]]
    source, native = OUTPUT / 'program.wasm', OUTPUT / 'native'
    exports = [value for name in ('unary', 'binary', 'character') for value in ('--export', name)]
    run([ROOT / 'scripts/build-sfir', *exports, ROOT / 'tests/sfir/scalar-services.sfir', source], 'compile')
    check_wasm(source, arguments, inputs)
    run([ROOT / 'scripts/build-native', '--wasm', '--entry-c', ROOT / 'tests/sfir/scalar-services.c',
         source, native], 'native-build')
    check_output(run([native, *arguments], 'native-run'), inputs)
    check_traps(native, traps)
    print(f'PASS {len(inputs)} scalar results and {len(traps)} narrowing traps on raw/optimized linked Wasm and native: {OUTPUT}')


if __name__ == '__main__':
    main()
