#!/usr/bin/env python3
"""Use request counters to verify direct, typed, opaque, and apply paths."""
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NODE = '/nix/store/lfaydgacdyngci7p60s8wwvgdm74fjkx-nodejs-24.19.0/bin/node'
HOST = ROOT / 'build/counting-host/scripts/run-counted.mjs'
PROGRAMS = {
    'd277-reference': Path('/tmp/snail-vector-reference-d2770ab-20261012/build/vector-append/reference/program.wasm'),
    'd4-reference': ROOT / 'build/vector-append/reference/program.wasm',
    'd4-public': ROOT / 'build/vector-append/public/program.wasm',
}
MODES = ['direct-three', 'typed-three', 'opaque-three', 'apply-three']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def instrument(label, program):
    directory = ROOT / 'build/vector-diagnostics' / label
    subprocess.run([sys.executable, str(ROOT/'build/instrument-vector.py'), str(program), str(directory)], check=True)
    return directory, json.loads((directory/'manifest.json').read_text())


def invoke(label, program, directory, manifest, mode, repetitions):
    output = directory / f'{mode}-{repetitions}'
    output.mkdir()
    source = f'{mode}\ninteger\n8\n{repetitions}\n#t\n'
    (output/'input.txt').write_text(source)
    command = ['taskset', '-c', '5', NODE, '--no-warnings', str(HOST), str(directory/'instrumented.wasm')]
    completed = subprocess.run(command,cwd=program.parent,input=source,text=True,capture_output=True,timeout=60)
    (output/'stdout.txt').write_text(completed.stdout)
    (output/'stderr.txt').write_text(completed.stderr)
    markers = [line.removeprefix('+!PROBES!+') for line in completed.stderr.splitlines() if line.startswith('+!PROBES!+')]
    if completed.returncode or len(markers)!=1 or '+!VECTOR_APPEND!+' not in completed.stdout:
        raise ValueError(f'counter execution failed: {output}')
    values = json.loads(markers[0])['counters']
    counts = [{**row, 'value': int(values[row['export']])} for row in manifest['counters']]
    (output/'counts.json').write_text(json.dumps(counts,indent=2)+'\n')
    record = {'label':label,'mode':mode,'size':8,'repetitions':repetitions,'element_kind':'integer',
              'command':command,'cwd':str(program.parent),'returncode':completed.returncode,'passed':True,
              'original_program_sha256':digest(program),'instrumented_sha256':manifest['instrumented_sha256'],
              'scope':'Whole invocation, including pre-run expected-checksum loop. Array-copy helper/path differences isolate append invocation frequency; total constructor slopes also include expected-checksum setup. No timing evidence; concurrent root typing tests may run.',
              'caveat':'Probes count reached requests before operands; physical materialization and optimizing-engine costs are not measured.'}
    (output/'result.json').write_text(json.dumps(record,indent=2)+'\n')
    return counts


def differences(first, last):
    return [{**b,'difference':b['value']-a['value'],'per_additional_iteration':(b['value']-a['value'])/10}
            for a,b in zip(first,last) if a['key']==b['key'] and a['value']!=b['value']]


def main():
    rows=[]
    for label,program in PROGRAMS.items():
        directory,manifest=instrument(label,program)
        for mode in MODES:
            first=invoke(label,program,directory,manifest,mode,3)
            last=invoke(label,program,directory,manifest,mode,13)
            delta=differences(first,last)
            row={'label':label,'mode':mode,'extra_iterations':10,'differential_request_counts':delta}
            (directory/(mode+'-difference.json')).write_text(json.dumps(row,indent=2)+'\n')
            rows.append(row)
            print(label,mode,'passed',flush=True)
    (ROOT/'build/vector-counter-summary.json').write_text(json.dumps(rows,indent=2)+'\n')


if __name__=='__main__':
    main()
