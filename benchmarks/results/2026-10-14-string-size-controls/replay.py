"""Restore the String size controls and check their unchanged Wasm artifacts."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile

REPORT = Path(sys.argv[1]).resolve()
RESTORE = Path(sys.argv[2]).resolve()


# ---- Match every archived member before running anything ----

def load(path):
    return json.loads(path.read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(manifest):
    for name, expected in manifest['files'].items():
        assert digest(RESTORE / name) == expected, name


def restore():
    manifest = load(REPORT / 'manifest.json')
    archive = REPORT / 'artifacts.tar.xz'
    assert digest(archive) == manifest['archive_sha256']
    RESTORE.mkdir(parents=True, exist_ok=False)
    with tarfile.open(archive) as source:
        assert sorted(source.getnames()) == sorted(manifest['files'])
        source.extractall(RESTORE, filter='data')
    verify(manifest)
    return manifest, load(RESTORE / 'path-map.json')


def relocated(value, mapping):
    return str(RESTORE / mapping[value]) if value in mapping else value


def verify_identities(record, mapping):
    for item in record['identities_before']:
        assert digest(Path(relocated(item['path'], mapping))) == item['sha256'], item


# ---- Use new count-one files; never alter archived inputs ----

def probe(variant, mapping, threshold):
    command = [relocated(arg, mapping) for arg in variant['command']]
    spec = load(Path(command[-1]))
    spec['count'] = 1
    target = RESTORE / f"probe-{threshold}-{variant['name']}.json"
    target.write_text(json.dumps(spec) + '\n')
    command[-1] = str(target)
    env = {key: value for key, value in os.environ.items()
           if key not in ('NODE_OPTIONS', 'SNAIL_NATIVE_GC_INTERVAL')
           and not key.startswith('SNAIL_GC_')}
    cwd = RESTORE / 'files' / variant['cwd'].lstrip('/')
    process = subprocess.run(command, cwd=cwd, env=env, text=True,
                             capture_output=True, timeout=120)
    result = dict(threshold=threshold, variant=variant['name'], command=command,
                  cwd=str(cwd), returncode=process.returncode,
                  stdout=process.stdout, stderr=process.stderr)
    assert process.returncode == 0 and not process.stderr, result
    value = json.loads(process.stdout)
    assert value['result'] == '1' and value['barriers'] is None
    assert value['setup_barriers'] is None
    return result


manifest, mapping = restore()
checks = []
for item in load(REPORT / 'inventory.json'):
    record = load(REPORT / str(item['threshold']) / 'clean.json')
    verify_identities(record, mapping)
    for variant in record['plan']['variants']:
        checks.append(probe(variant, mapping, item['threshold']))
    verify_identities(record, mapping)
verify(manifest)
result = dict(scope='Relocated count-one correctness only, not performance samples.',
              archive_sha256=manifest['archive_sha256'], verified_members=len(manifest['files']),
              archived_and_external_identities_unchanged=True, probes=checks)
(REPORT / 'replay-check.json').write_text(json.dumps(result, indent=2) + '\n')
print(len(checks), 'probes passed;', len(manifest['files']), 'members verified')
