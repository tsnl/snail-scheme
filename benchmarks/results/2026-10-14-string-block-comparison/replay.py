"""Hash-check archived comparisons and execute count-one relocation probes."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile

REPORT = Path(sys.argv[1]).resolve()
NAME = REPORT.name.removeprefix('2026-10-14-')
RESTORE = Path(sys.argv[2]).resolve()


# ---- Restore only the archived members whose hashes were published ----

def load(path):
    return json.loads(path.read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


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


def verify(manifest):
    for path, expected in manifest['files'].items():
        assert digest(RESTORE / path) == expected, path


def relocate(value, mapping):
    return str(RESTORE / mapping[value]) if value in mapping else value


# ---- Change only the repetition count; retain canonical problem inputs ----

def reduced_command(variant, mapping, number):
    command = [relocate(arg, mapping) for arg in variant['command']]
    data = variant['stdin']
    if data is not None:
        data = '1\n' + data.split('\n', 1)[1]
    elif command[-1].endswith('.json'):
        spec = load(Path(command[-1]))
        spec['count'] = 1
        target = RESTORE / f'probe-{number}.json'
        target.write_text(json.dumps(spec) + '\n')
        command[-1] = str(target)
    else:
        original = Path(command[-1]).read_text()
        target = RESTORE / f'probe-{number}.txt'
        target.write_text('1 ' + original.split(' ', 1)[1])
        command[-1] = str(target)
    return command, data


def variants(record):
    if NAME in ('string-storage', 'string-block-comparison'):
        return record['plan']['variants']
    return [dict(name=o['variant'], command=o['command'], cwd=o['cwd'],
                 stdin=o['stdin'], environment={},
                 kind='json' if o['variant'] == 'strict' else 'csv',
                 expected='1' if o['variant'] == 'strict' else 'Result: 2005')
            for o in record['observations'][:4]]


def check_result(variant, output):
    assert 'INCORRECT' not in output
    if variant['kind'] == 'json':
        result = json.loads(output)
        assert result['result'] == variant['expected']
        assert result['barriers'] is None and result['setup_barriers'] is None
    else:
        rows = [line.removeprefix('+!CSVLINE!+').split(',') for line in output.splitlines()
                if line.startswith('+!CSVLINE!+')]
        assert len(rows) == 1 and rows[0][1].endswith(':1'), output
        if variant['name'] not in ('original-chez', 'adapted-chez'):
            assert [line for line in output.splitlines() if line.startswith('Result:')] == [variant['expected']]


# ---- These executions check portability and results, not performance ----

def probe(variant, mapping, number):
    command, data = reduced_command(variant, mapping, number)
    cwd = RESTORE / 'files' / variant['cwd'].lstrip('/')
    assert cwd.is_dir(), cwd
    env = {key: value for key, value in os.environ.items()
           if key not in ('NODE_OPTIONS', 'SNAIL_NATIVE_GC_INTERVAL') and not key.startswith('SNAIL_GC_')}
    env.update(variant['environment'])
    process = subprocess.run(command, cwd=cwd, env=env, input=data,
                             text=True, capture_output=True, timeout=120)
    item = dict(variant=variant['name'], command=command, cwd=str(cwd), stdin=data,
                returncode=process.returncode, stdout=process.stdout, stderr=process.stderr)
    assert process.returncode == 0 and not process.stderr, item
    check_result(variant, process.stdout)
    return item


manifest, mapping = restore()
record = load(REPORT / 'clean.json')
checks = [probe(variant, mapping, n) for n, variant in enumerate(variants(record))]
verify(manifest)
result = dict(archive_sha256=manifest['archive_sha256'], verified_members=len(manifest['files']),
              original_archive_members_unchanged=True, repetitions=1,
              scope='Relocated correctness probes only; not performance samples.', probes=checks)
(REPORT / 'replay-check.json').write_text(json.dumps(result, indent=2) + '\n')
print(NAME, len(checks), 'replay probes passed;', len(manifest['files']), 'members verified')
