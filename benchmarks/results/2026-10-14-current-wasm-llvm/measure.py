"""Compare frozen current Wasm on V8 and the archived Immix native path."""

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


# ---- Frozen inputs and exact external programs ----

def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def identities(files):
    return [{'path': name, 'sha256': hashlib.sha256(Path(name).read_bytes()).hexdigest()}
            for name in sorted(set(files))]


def environment(overrides):
    values = {key: value for key, value in os.environ.items()
              if key not in ('NODE_OPTIONS', 'SNAIL_NATIVE_GC_INTERVAL')
              and not key.startswith('SNAIL_GC_')}
    values.update(overrides)
    return values


# ---- Fresh processes preserve predicates, counts and configuration failures ----

def execute(variant, cpu, taskset):
    command = [taskset, '-c', str(cpu), *variant['command']]
    started = time.monotonic()
    try:
        result = subprocess.run(command, cwd=variant['cwd'], env=environment(variant.get('environment', {})),
                                text=True, capture_output=True, timeout=900)
        return dict(command=command, cwd=variant['cwd'], environment=variant.get('environment', {}),
                    returncode=result.returncode, stdout=result.stdout, stderr=result.stderr,
                    process_seconds=time.monotonic() - started)
    except subprocess.TimeoutExpired as error:
        return dict(command=command, cwd=variant['cwd'], environment=variant.get('environment', {}),
                    returncode=None, timeout=True, stdout=(error.stdout or b'').decode(),
                    stderr=(error.stderr or b'').decode(), process_seconds=time.monotonic() - started)


def check(item, expected):
    assert item['returncode'] == 0 and not item['stderr'], item
    result = json.loads(item['stdout'])
    assert result['result'] == str(expected) and result['barriers'] is None, result
    assert result['setup_barriers'] is None, result
    assert math.isfinite(result['seconds']) and result['seconds'] > 0, result
    item['workload_seconds'] = result['seconds']
    item['guest_report'] = result


def observe(record, case, variant, round_number, output):
    item = dict(execute(variant, record['cpu'], record['plan']['taskset']),
                benchmark=case['name'], variant=variant['name'], round=round_number,
                retained=round_number >= 0)
    record['observations'].append(item)
    save(output, record)
    check(item, case['expected'])
    save(output, record)
    print(round_number, case['name'], variant['name'], item['workload_seconds'], flush=True)


# ---- Balanced ordinal positions; retain every observation and its provenance ----

def finish(record, output):
    record['identities_after'] = identities(record['plan']['files'])
    assert record['identities_before'] == record['identities_after']
    summaries = {}
    for case in record['plan']['cases']:
        summaries[case['name']] = {}
        for variant in case['variants']:
            samples = [item['workload_seconds'] for item in record['observations']
                       if item['benchmark'] == case['name'] and item['variant'] == variant['name'] and item['retained']]
            assert len(samples) == 4
            summaries[case['name']][variant['name']] = dict(samples=samples,
                median=statistics.median(samples), min=min(samples), max=max(samples))
    record.update(summary=summaries, complete=True,
                  finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    save(output, record)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('plan', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    assert not args.output.exists(), 'Keep prior observations; choose a new output path.'
    plan = json.loads(args.plan.read_text())
    initial = identities(plan['files'])
    assert initial == plan['identities'], 'Source, artifact or tool changed after preparation.'
    record = dict(plan=plan, cpu=plan['cpu'], identities_before=initial, observations=[], complete=False,
                  scope='Original inputs/counts, setup excluded and final predicates included. One discarded round, four retained fresh-process rounds; all cases rotate ordinal positions and both implementations alternate.',
                  started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    for round_number in [-1, 0, 1, 2, 3]:
        cases = plan['cases']
        shift = max(round_number, 0) % len(cases)
        for case in cases[shift:] + cases[:shift]:
            variants = case['variants']
            if max(round_number, 0) % 2:
                variants = variants[::-1]
            for variant in variants:
                observe(record, case, variant, round_number, args.output)
    finish(record, args.output)


if __name__ == '__main__':
    main()
