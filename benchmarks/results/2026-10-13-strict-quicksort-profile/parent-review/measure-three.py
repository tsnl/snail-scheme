"""Compare the frozen quicksort module, its reassembly, and private helpers."""

from pathlib import Path
import datetime
import hashlib
import json
import os
import statistics
import subprocess
import sys
import time


# ---- Frozen inputs and fresh processes ----

root, output = map(Path, sys.argv[1:])
node = Path('/nix/store/lfaydgacdyngci7p60s8wwvgdm74fjkx-nodejs-24.19.0/bin/node')
taskset = Path('/run/current-system/sw/bin/taskset')
host = root / 'original/host.mjs'
spec = root / 'original/quicksort/spec.json'
variants = {
    'original': root / 'original/quicksort/strict.wasm',
    'reassembled': root / 'verification/original-reassembled.wasm',
    'direct-parameters': root / 'allocation-ablation/module.wasm',
}
env = os.environ.copy()
env.pop('NODE_OPTIONS', None)


def identities():
    paths = dict(variants, node=node, taskset=taskset, host=host, spec=spec,
                 driver=Path(__file__))
    return {key: {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
            for key, path in paths.items()}


def observe(name):
    command = [str(taskset), '-c', '5', str(node), str(host), str(variants[name]), str(spec)]
    started = time.monotonic()
    process = subprocess.run(command, env=env, capture_output=True, text=True, timeout=60)
    return {'variant': name, 'command': command, 'returncode': process.returncode,
            'stdout': process.stdout, 'stderr': process.stderr,
            'process_seconds': time.monotonic() - started}


# ---- Discarded trio and balanced retained observations ----

initial = identities()
config = json.loads(spec.read_text())
assert config['count'] == 2500 and config['inputs'] == [10000, 1000000]
record = {
    'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'scope': 'Uninstrumented workload timing; initialization excluded, V8 tiering included.',
    'intervention': 'Private closure representation, direct parameters, captured loads/readiness and redundant checks together.',
    'cpu': 5, 'node_options': None, 'identities_before': initial, 'observations': [],
}
names = list(variants)
for round_index in range(4):
    offset = round_index % 3
    for name in names[offset:] + names[:offset]:
        result = dict(observe(name), round=round_index, discarded=round_index == 0)
        record['observations'].append(result)
        output.write_text(json.dumps(record, indent=2) + '\n')
        assert result['returncode'] == 0, result
        measured = json.loads(result['stdout'])
        assert measured['result'] == '1' and measured['barriers'] is None
        assert measured['setup_barriers'] is None and measured['seconds'] > 0
        result['workload_seconds'] = measured['seconds']

record['identities_after'] = identities()
assert record['identities_after'] == initial
record['summary'] = {}
for name in names:
    samples = [r['workload_seconds'] for r in record['observations']
               if r['variant'] == name and not r['discarded']]
    record['summary'][name] = {'samples': samples, 'median': statistics.median(samples),
                               'min': min(samples), 'max': max(samples)}
record['ratios'] = {
    'reassembled_over_original': record['summary']['reassembled']['median'] / record['summary']['original']['median'],
    'direct_over_original': record['summary']['direct-parameters']['median'] / record['summary']['original']['median'],
    'direct_over_reassembled': record['summary']['direct-parameters']['median'] / record['summary']['reassembled']['median'],
}
record['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
output.write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps({'summary': record['summary'], 'ratios': record['ratios']}, indent=2))
