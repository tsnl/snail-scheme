"""Execute the public SFIR command, including publication and cleanup failures."""

import json
import os
from pathlib import Path
import signal
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'build/sfir-command'
RECORDS = []


def invoke(arguments, status=0, error=None, input_text=None, expected_output=None, **environment):
    command = [str(value) for value in arguments]
    process = subprocess.Popen(command, cwd=ROOT, stdin=subprocess.PIPE if input_text is not None else None,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, start_new_session=True, env={**os.environ, **environment})
    try:
        stdout, stderr = process.communicate(input=input_text, timeout=240)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise
    RECORDS.append(dict(command=command, status=process.returncode, stdin=input_text, stdout=stdout, stderr=stderr))
    (OUTPUT / 'commands.json').write_text(json.dumps(RECORDS, indent=2) + '\n')
    assert process.returncode == status, RECORDS[-1]
    assert error is None or error in stderr, RECORDS[-1]
    assert expected_output is None or expected_output == stdout, RECORDS[-1]


def source(name, text):
    path = OUTPUT / (name + '.sfir')
    path.write_text(text + '\n')
    return path


def statuses(target):
    for name, text, status in [('answer with space', '42', 42), ('too-large', '256', 1),
                               ('negative', '-1', 1), ('unit', '(ref-set! (ref 0) 1)', 0)]:
        path = source(name, '(import (sfir primitive))\n' + text)
        invoke([ROOT / 'snail-sfir', 'run', '--target', target, path, '--help', '-I', '', 'a b'], status)


def publication(target):
    output = OUTPUT / ('published.wasm' if target == 'wasm' else 'published')
    command = [ROOT / 'snail-sfir', 'compile', '--target', target, '-o', output]
    valid = source('valid', '42')
    invoke([*command, valid])
    before = output.read_bytes()
    invoke([*command, source('float', '1.5')], 1, 'command result must be')
    assert output.read_bytes() == before
    invoke([*command, valid], 1, 'wasm-opt', WASM_OPT='/missing/wasm-opt')
    assert output.read_bytes() == before
    host = [os.environ.get('NODE', 'node'), ROOT / 'scripts/run-sfir.mjs', output] if target == 'wasm' else [output]
    invoke(host, 42)


def cleanup(target):
    output = OUTPUT / ('cleanup-' + target + '.txt')
    path = source('cleanup-' + target, f'''(import (sfir core) (sfir io))
(define port (open-output-file {json.dumps(str(output))}))
(write-string "buffered before trap" port)
(vector-ref (vector 1) 2)''')
    invoke([ROOT / 'snail-sfir', 'run', '--target', target, path], 1)
    assert output.read_text() == 'buffered before trap'


def standard_input(target):
    artifact = OUTPUT / ('stdin.wasm' if target == 'wasm' else 'stdin')
    invoke([ROOT / 'snail-sfir', 'compile', '--target', target, '-o', artifact,
            ROOT / 'tests/sfir/standard-input.sfir'])
    host = [os.environ.get('NODE', 'node'), ROOT / 'scripts/run-sfir.mjs', artifact] if target == 'wasm' else [artifact]
    for text in ('λ😀\n\0é', ''):
        invoke(host, input_text=text, expected_output=text)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    invoke([ROOT / 'snail-sfir', '--help'], CHIBI='/missing/chibi', WASM_OPT='/missing/wasm-opt')
    for target in ('wasm', 'native'):
        statuses(target)
        publication(target)
        cleanup(target)
        standard_input(target)
        print('PASS public SFIR command:', target, flush=True)
    path = source('protected', '42')
    invoke([ROOT / 'snail-sfir', 'compile', '-o', path, path], 1, 'must not replace')
    assert path.read_text() == '42\n'


if __name__ == '__main__':
    main()
