#!/usr/bin/env python3
"""Repeat the recorded timing protocol using a restored, verified archive."""

import argparse
import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import time


# ---- Relocate archived programs; retain and verify external tools ----

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def relocated(path, archive, mapping):
    return str(archive / mapping[path]) if path in mapping else path


def identities(original, archive, mapping):
    result = []
    for item in original['identities_before']:
        path = relocated(item['path'], archive, mapping)
        assert digest(path) == item['sha256'], path
        result.append(dict(path=path, sha256=item['sha256']))
    return result


def observe(reference, archive, mapping):
    command = [relocated(argument, archive, mapping) for argument in reference['command']]
    cwd = archive / 'files' / reference['cwd'].lstrip('/')
    environment = os.environ.copy()
    environment.pop('NODE_OPTIONS', None)
    started = time.monotonic()
    result = execute(command, cwd, environment, reference['stdin'])
    return dict(result, variant=reference['variant'], command=command, cwd=str(cwd),
                stdin=reference['stdin'], process_seconds=time.monotonic() - started)


def execute(command, cwd, environment, data):
    try:
        process = subprocess.run(command, cwd=cwd, env=environment, input=data,
                                 capture_output=True, text=True, timeout=900)
        return dict(returncode=process.returncode, stdout=process.stdout, stderr=process.stderr)
    except subprocess.TimeoutExpired as error:
        return dict(returncode=None, timeout=True, stdout=(error.stdout or b'').decode(),
                    stderr=(error.stderr or b'').decode())


# ---- Require the original result contract for every observation ----

def csv_record(output):
    rows = [line.removeprefix('+!CSVLINE!+').split(',') for line in output.splitlines()
            if line.startswith('+!CSVLINE!+')]
    assert len(rows) == 1 and len(rows[0]) == 3
    return rows[0]


def csv_seconds(reference, observation):
    expected, actual = csv_record(reference['stdout']), csv_record(observation['stdout'])
    assert expected[:2] == actual[:2]
    if reference['variant'] == 'rust-wasm':
        expected_results = [line for line in reference['stdout'].splitlines() if line.startswith('Result:')]
        actual_results = [line for line in observation['stdout'].splitlines() if line.startswith('Result:')]
        assert expected_results == actual_results and len(actual_results) == 1
    return float(actual[2])


def checked_seconds(reference, observation):
    assert observation['returncode'] == 0 and not observation['stderr'], observation
    if reference['variant'] in ('original-chez', 'adapted-chez', 'rust-wasm'):
        seconds = csv_seconds(reference, observation)
    else:
        expected, actual = json.loads(reference['stdout']), json.loads(observation['stdout'])
        assert {key: value for key, value in actual.items() if key != 'seconds'} == {
            key: value for key, value in expected.items() if key != 'seconds'}
        seconds = actual['seconds']
    assert math.isfinite(seconds) and seconds > 0
    return seconds


def run_rounds(record, original, archive, mapping, output):
    references = {name: next(item for item in original['observations'] if item['variant'] == name)
                  for name in original['order']}
    names = original['order']
    for round_index in range(-1, len(names)):
        offset = max(round_index, 0)
        for name in names[offset:] + names[:offset]:
            item = dict(observe(references[name], archive, mapping), round=round_index, retained=round_index >= 0)
            record['observations'].append(item)
            save(output, record)
            item['workload_seconds'] = checked_seconds(references[name], item)
            save(output, record)
            print(round_index, name, item['workload_seconds'], flush=True)


def finish(record, original, archive, mapping, output):
    record['identities_after'] = identities(original, archive, mapping)
    assert record['identities_after'] == record['identities_before']
    record['summary'] = {}
    for name in original['order']:
        samples = [item['workload_seconds'] for item in record['observations'] if item['variant'] == name and item['retained']]
        record['summary'][name] = dict(samples=samples, median=statistics.median(samples), min=min(samples), max=max(samples))
    record['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    record['complete'] = True
    save(output, record)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('benchmark', choices=('quicksort', 'graphs', 'mperm', 'simplex'))
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    archive = args.archive.resolve()
    mapping = json.loads((archive / 'path-map.json').read_text())
    matches = [value for key, value in mapping.items() if key.endswith(f'/build/call-capture-measurements/{args.benchmark}.json')]
    assert len(matches) == 1
    original = json.loads((archive / matches[0]).read_text())
    record = dict(benchmark=args.benchmark, started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  scope=original['scope'], order=original['order'], cpu=original['cpu'], node_options=None,
                  identities_before=identities(original, archive, mapping), observations=[], complete=False)
    run_rounds(record, original, archive, mapping, args.output)
    finish(record, original, archive, mapping, args.output)


if __name__ == '__main__':
    main()
