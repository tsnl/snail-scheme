"""Run a frozen workload comparison without conflating diagnostics and timing."""

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


# ---- Preserve exact inputs, artifacts and tool identities ----

def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def identities(files):
    return [dict(path=path, sha256=hashlib.sha256(Path(path).read_bytes()).hexdigest()) for path in files]


def environment(overrides):
    values = {key: value for key, value in os.environ.items()
              if key not in ('NODE_OPTIONS', 'SNAIL_NATIVE_GC_INTERVAL') and not key.startswith('SNAIL_GC_')}
    values.update(overrides)
    return values


# ---- Always save a failed process before checking its original result ----

def execute(variant, plan):
    command = [plan['taskset'], '-c', str(plan['cpu']), *variant['command']]
    start = time.monotonic()
    try:
        process = subprocess.run(command, cwd=variant['cwd'], env=environment(variant['environment']),
            input=variant['stdin'], text=True, capture_output=True, timeout=900)
        return dict(command=command, returncode=process.returncode, stdout=process.stdout,
                    stderr=process.stderr, process_seconds=time.monotonic() - start)
    except subprocess.TimeoutExpired as error:
        return dict(command=command, returncode=None, timeout=True, stdout=(error.stdout or b'').decode(),
                    stderr=(error.stderr or b'').decode(), process_seconds=time.monotonic() - start)


def seconds(variant, observation):
    assert observation['returncode'] == 0 and not observation['stderr'], observation
    if variant['kind'] == 'json':
        result = json.loads(observation['stdout'])
        assert result['result'] == variant['expected'] and result['barriers'] is None
        assert result['setup_barriers'] is None
        observation['guest_report'] = result
        return result['seconds']
    lines = observation['stdout'].splitlines()
    assert [line for line in lines if line.startswith('Result:')] == [variant['expected']]
    rows = [line.removeprefix('+!CSVLINE!+').split(',') for line in lines if line.startswith('+!CSVLINE!+')]
    assert len(rows) == 1 and len(rows[0]) == 3 and rows[0][:2] == ['rust-wasm', variant['csv_case']]
    assert not any('INCORRECT' in line or line.startswith('Audit:') for line in lines)
    return float(rows[0][2])


def observe(record, variant, round_number, output):
    item = dict(execute(variant, record['plan']), variant=variant['name'],
                round=round_number, retained=round_number >= 0)
    record['observations'].append(item)
    save(output, record)
    item['workload_seconds'] = seconds(variant, item)
    assert math.isfinite(item['workload_seconds']) and item['workload_seconds'] > 0, item
    save(output, record)
    print(round_number, variant['name'], item['workload_seconds'], flush=True)


# ---- Rotate every variant through every ordinal position ----

def finish(record, output):
    record['identities_after'] = identities(record['plan']['files'])
    assert record['identities_before'] == record['identities_after']
    summary = {}
    for variant in record['plan']['variants']:
        samples = [item['workload_seconds'] for item in record['observations']
                   if item['retained'] and item['variant'] == variant['name']]
        assert len(samples) == record['plan']['rounds']
        summary[variant['name']] = dict(samples=samples, median=statistics.median(samples), min=min(samples), max=max(samples))
    record.update(summary=summary, complete=True, finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    save(output, record)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('plan', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    assert not args.output.exists(), 'Preserve prior observations; choose another output path.'
    plan = json.loads(args.plan.read_text())
    initial = identities(plan['files'])
    assert initial == plan['identities'] and plan['rounds'] == len(plan['variants'])
    record = dict(plan=plan, identities_before=initial, observations=[], complete=False,
                  started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    for round_number in range(-1, plan['rounds']):
        shift = max(round_number, 0)
        variants = plan['variants'][shift:] + plan['variants'][:shift]
        for variant in variants:
            observe(record, variant, round_number, args.output)
    finish(record, args.output)


if __name__ == '__main__':
    main()
