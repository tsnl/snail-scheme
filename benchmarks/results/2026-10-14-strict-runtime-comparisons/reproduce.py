#!/usr/bin/env python3
"""Repeat a recorded comparison from its restored, verified artifact archive."""

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


# ---- Resolve archived files while retaining exact external tools ----

def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def relocated(path, archive, mapping):
    return str(archive / mapping[path]) if path in mapping else path


def identities(original, archive, mapping):
    result = []
    for item in original['identities_before']:
        path = relocated(item['path'], archive, mapping)
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == item['sha256'], path
        result.append(dict(path=path, sha256=item['sha256']))
    return result


def variant(observation):
    return observation.get('variant', observation.get('policy'))


# ---- Fresh processes retain the recorded order, inputs and result contract ----

def execute(command, cwd, data):
    environment = os.environ.copy()
    environment.pop('NODE_OPTIONS', None)
    try:
        process = subprocess.run(command, cwd=cwd, env=environment, input=data,
                                 capture_output=True, text=True, timeout=900)
        return dict(returncode=process.returncode, stdout=process.stdout, stderr=process.stderr)
    except subprocess.TimeoutExpired as error:
        return dict(returncode=None, timeout=True, stdout=(error.stdout or b'').decode(),
                    stderr=(error.stderr or b'').decode())


def observe(reference, archive, mapping):
    command = [relocated(argument, archive, mapping) for argument in reference['command']]
    cwd = archive / 'files' / reference['cwd'].lstrip('/')
    started = time.monotonic()
    result = execute(command, cwd, reference.get('stdin'))
    return dict(result, variant=variant(reference), command=command, cwd=str(cwd),
                stdin=reference.get('stdin'), process_seconds=time.monotonic() - started,
                round=reference['round'], retained=reference['retained'])


def csv_record(output):
    rows = [line.removeprefix('+!CSVLINE!+').split(',') for line in output.splitlines()
            if line.startswith('+!CSVLINE!+')]
    assert len(rows) == 1 and len(rows[0]) == 3
    return rows[0]


def csv_seconds(reference, observation):
    expected, actual = csv_record(reference['stdout']), csv_record(observation['stdout'])
    assert expected[:2] == actual[:2]
    if variant(reference) == 'rust-wasm':
        results = [line for line in observation['stdout'].splitlines() if line.startswith('Result:')]
        expected_results = [line for line in reference['stdout'].splitlines() if line.startswith('Result:')]
        assert results == expected_results and len(results) == 1
    return float(actual[2])


def checked_seconds(reference, observation):
    assert observation['returncode'] == 0 and not observation['stderr'], observation
    assert 'INCORRECT' not in observation['stdout']
    if variant(reference) in ('original-chez', 'adapted-chez', 'rust-wasm'):
        seconds = csv_seconds(reference, observation)
    else:
        expected, actual = json.loads(reference['stdout']), json.loads(observation['stdout'])
        assert {k: v for k, v in actual.items() if k != 'seconds'} == {
            k: v for k, v in expected.items() if k != 'seconds'}
        seconds = actual['seconds']
    assert math.isfinite(seconds) and seconds > 0
    return seconds


def run(record, original, archive, mapping, output):
    for reference in original['observations']:
        item = observe(reference, archive, mapping)
        record['observations'].append(item)
        save(output, record)
        item['workload_seconds'] = checked_seconds(reference, item)
        save(output, record)
        print(item['round'], item['variant'], item['workload_seconds'], flush=True)


def finish(record, original, archive, mapping, output):
    record['identities_after'] = identities(original, archive, mapping)
    assert record['identities_after'] == record['identities_before']
    record['summary'] = {}
    for name in dict.fromkeys(variant(item) for item in original['observations']):
        samples = [item['workload_seconds'] for item in record['observations']
                   if item['variant'] == name and item['retained']]
        record['summary'][name] = dict(samples=samples, median=statistics.median(samples),
                                      min=min(samples), max=max(samples))
    record['complete'] = True
    record['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    save(output, record)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('comparison', choices=('deriv', 'mbrotZ', 'graphs-callbacks', 'mperm-policies'))
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    assert not args.output.exists(), 'Choose a new output path to retain earlier observations.'
    archive = args.archive.resolve()
    mapping = json.loads((archive / 'path-map.json').read_text())
    records = json.loads((archive / 'comparisons.json').read_text())
    original = json.loads((archive / records[args.comparison]).read_text())
    record = dict(comparison=args.comparison, scope=original['scope'], cpu=original['cpu'],
                  started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  node_options=None, identities_before=identities(original, archive, mapping),
                  observations=[], complete=False)
    run(record, original, archive, mapping, args.output)
    finish(record, original, archive, mapping, args.output)


if __name__ == '__main__':
    main()
