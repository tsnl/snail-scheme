"""Preserve the clean comparison separately from the archived native experiment."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parent.parent
EXPERIMENT = Path('/tmp/snail-current-wasm-llvm-20261014')
REPORT = ROOT / 'benchmarks/results/2026-10-14-current-wasm-llvm'
RESTORED = Path('/tmp/snail-current-wasm-llvm-replay-20261014')
MEASUREMENTS = ROOT / 'build/current-wasm-llvm-comparison'


def load(path):
    return json.loads(path.read_text())


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


# ---- Verify every clean observation and frozen file before publication ----

record = load(MEASUREMENTS / 'observations.json')
assert record['complete'] and len(record['observations']) == 40
assert record['identities_before'] == record['identities_after']
for item in record['identities_after']:
    assert digest(Path(item['path'])) == item['sha256'], item
for round_number in range(4):
    observations = [item for item in record['observations'] if item['round'] == round_number]
    assert len(observations) == 8
    expected = record['plan']['cases']
    expected = expected[round_number:] + expected[:round_number]
    assert [item['benchmark'] for item in observations[::2]] == [case['name'] for case in expected]
    assert all((item['variant'] == 'v8') == (round_number % 2 == 0) for item in observations[::2])

shutil.copytree(EXPERIMENT / REPORT.relative_to(ROOT), REPORT)
for source, target in [('observations.json', 'clean.json'), ('quiet-window.json', 'quiet-window.json'),
                       ('plan.json', 'plan.json')]:
    shutil.copyfile(MEASUREMENTS / source, REPORT / target)
for source, target in [('measure-current-llvm.py', 'measure.py'), ('freeze-current-llvm.py', 'freeze.py'),
                       ('archive-current-llvm.py', 'archive.py')]:
    shutil.copyfile(ROOT / 'build' / source, REPORT / target)


# ---- Restore the exact executables and all retained diagnostics ----

archive = REPORT / 'artifacts.tar.xz'
assert digest(archive) == load(REPORT / 'archive.json')['archive_sha256']
RESTORED.mkdir(exist_ok=False)
with tarfile.open(archive) as source:
    members = source.getmembers()
    assert all(member.isfile() and not Path(member.name).is_absolute()
               and '..' not in Path(member.name).parts for member in members)
    assert len({member.name for member in members}) == len(members)
    hashes = {member.name: hashlib.sha256(source.extractfile(member).read()).hexdigest() for member in members}
    source.extractall(RESTORED, filter='data')
assert all(digest(RESTORED / name) == expected for name, expected in hashes.items())
for item in record['identities_after']:
    path = Path(item['path'])
    if path.is_relative_to(EXPERIMENT):
        relative = path.relative_to(EXPERIMENT)
        if relative.is_relative_to('build/current-wasm-llvm'):
            restored = RESTORED / 'artifacts' / relative.relative_to('build/current-wasm-llvm')
        else:
            restored = RESTORED / 'sources' / relative
        assert digest(restored) == item['sha256'], item
save(REPORT / 'manifest.json', dict(archive_sha256=digest(archive), files=hashes))


# ---- Bounded execution checks the restored artifacts, never supplies timings ----

observations = []
node_host = RESTORED / 'sources/experiments/current-wasm-llvm/node-host.mjs'
environment = {key: value for key, value in os.environ.items()
               if key not in ('NODE_OPTIONS', 'SNAIL_NATIVE_GC_INTERVAL') and not key.startswith('SNAIL_GC_')}
for case in record['plan']['cases']:
    directory = RESTORED / 'artifacts' / case['name']
    specification = load(directory / 'spec.json')
    specification['count'] = 1
    save(directory / 'replay-spec.json', specification)
    lines = (directory / 'inputs.txt').read_text().splitlines()
    first = lines[0].split()
    first[0] = '1'
    (directory / 'replay-inputs.txt').write_text(' '.join(first) + '\n' + '\n'.join(lines[1:]) + '\n')
    for variant in case['variants']:
        if variant['name'] == 'v8':
            command = [variant['command'][0], str(node_host), str(directory / 'input.wasm'),
                       str(directory / 'replay-spec.json'), '--validate']
        else:
            command = [str(directory / 'native'), str(directory / 'replay-inputs.txt'), '--validate']
        result = subprocess.run(command, env=dict(environment, **variant['environment']),
                                text=True, capture_output=True, timeout=180)
        observation = dict(benchmark=case['name'], variant=variant['name'], command=command,
                           environment=variant['environment'], returncode=result.returncode,
                           stdout=result.stdout, stderr=result.stderr)
        observations.append(observation)
        save(REPORT / 'replay-check.json', dict(scope='Count-one correctness probes after restoring exact artifacts; original non-count inputs retained. Not performance samples.',
             restored=str(RESTORED), files_verified=len(hashes), observations=observations, complete=False))
        assert result.returncode == 0 and not result.stderr, observation
        reported = json.loads(result.stdout)
        assert reported['result'] == str(case['expected']), observation
        assert reported['barriers'] == specification['barriers_per_iteration'], observation
final = load(REPORT / 'replay-check.json')
final['complete'] = True
save(REPORT / 'replay-check.json', final)
print(json.dumps(dict(files=len(hashes), replay_observations=len(observations), archive_sha256=digest(archive))))
