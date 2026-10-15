"""Freeze original String workloads and explicit storage controls before timing."""

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
STRICT = Path('/tmp/snail-strict-string-preparation-20261014-r3')
WIDTH = Path('/tmp/snail-strict-string-measurement-20261014/build/string-width')
HANDOFF = Path('/tmp/snail-rust-string-controls-20261014/build/rust-string-controls/timing-handoff/handoff.json')
NATIVE = Path('/tmp/snail-current-wasm-llvm-20261014/build/current-wasm-llvm')
TASKSET = '/run/current-system/sw/bin/taskset'
files = {str(Path(__file__).resolve()), str(ROOT / 'measure-storage.py'), str(HANDOFF), TASKSET}


def load(path):
    return json.loads(Path(path).read_text())


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def verify(path, expected):
    assert digest(path) == expected, path
    files.add(str(path))


# ---- Original source, complete result checks, and the exact width delta ----

handoff = load(HANDOFF)
node = handoff['cases'][0]['command'][0]
files.update([node, str(handoff['build_provenance']), str(STRICT / 'host.mjs'),
              str(STRICT / 'string/spec.json'), str(WIDTH / 'preparation.json'), str(WIDTH / 'checks.json')])
spec = load(STRICT / 'string/spec.json')
assert spec['count'] == 100 and spec['expected'] == 1
width = load(WIDTH / 'preparation.json')
checks = load(WIDTH / 'checks.json')
assert checks['complete'] and checks['noncustom_sections_identical']
assert all(item['passed'] for item in checks['observations'])
assert checks['identities_before'] == checks['identities_after']
for item in checks['identities_after']:
    verify(item['path'], item['sha256'])
verify(STRICT / 'string/strict.wasm', width['original_wasm_sha256'])
verify(width['source'], width['source_sha256'])
verify(width['wasm_as'], width['wasm_as_sha256'])
for item in width['observations']:
    stem = item['name'] + ('-observer' if item['observer'] else '')
    verify(WIDTH / (stem + '.wat'), item['wat_sha256'])
    verify(WIDTH / (stem + '.wasm'), item['wasm_sha256'])


# ---- One normal V8 host for all three GC representations ----

variants = []
for name, artifact in [('gc-i32-canonical', STRICT / 'string/strict.wasm'),
                       ('gc-i32-reassembled', WIDTH / 'i32.wasm'),
                       ('gc-i8-ascii', WIDTH / 'packed-i8.wasm')]:
    variants.append(dict(name=name, kind='json', expected='1',
        command=[node, str(STRICT / 'host.mjs'), str(artifact), str(STRICT / 'string/spec.json')],
        cwd=str(STRICT / 'string'), environment={}, stdin=None))


# ---- Frozen Rust controls retain their own documented ownership contracts ----

for case in handoff['cases']:
    assert case['count'] == spec['count'] and '--audit' not in case['command']
    assert Path(case['stdin']).read_text() == '100\n500000\n524278\n'
    for field, hash_field in [('artifact', 'wasm_sha256'), ('host', 'host_sha256'),
                             ('stdin', 'input_sha256'), ('module_source', 'module_source_sha256')]:
        verify(case[field], case[hash_field])
    for name, expected in case['source_bundle_hashes'].items():
        verify(Path(case['exact_source_bundle']) / name, expected)
    for name, expected in case.get('dependency_source_hashes', {}).items():
        verify(Path(case['dependency_source_root']) / name, expected)
    verify(case['correctness']['report'], case['correctness']['report_sha256'])
    assert case['correctness']['full_canonical_pass'] and case['correctness']['all_case_checks_pass']
    variants.append(dict(name='rust-original' if case['name'] == 'string' else 'rust-' + case['name'],
        kind='csv', csv_case=case['correctness']['csv_case'], expected=case['correctness']['expected_stdout_result'],
        command=case['command'], cwd=case['cwd'], environment={}, stdin=case['input_text']))


# ---- Native is a separate executor reference, with an eight-byte layout ----

native = next(case for case in load(NATIVE / 'handoff.json')['cases'] if case['benchmark'] == 'string')
files.update([str(NATIVE / 'handoff.json'), native['manifest']])
for path, expected in load(native['manifest'])['sha256'].items():
    verify(path, expected)
variant = native['variants']['native_immix_300mib']
variants.append(dict(variant, name='native-immix-eight-byte', kind='json', expected='1',
                     cwd=str(NATIVE / 'string'), stdin=None))
assert len(variants) == 9
plan = dict(name='string-storage', variants=variants, cpu=5, taskset=TASKSET,
            rounds=len(variants), files=sorted(files), rust_handoff=handoff,
            identities=[dict(path=path, sha256=digest(path)) for path in sorted(files)],
            protocol='One discarded round plus nine retained cyclic rotations: every variant appears once in every ordinal position. Original100 iterations, ten trials, threshold500000, result524278. No diagnostic or payload-audit mode in timing.')
(ROOT / 'string-storage-plan.json').write_text(json.dumps(plan, indent=2) + '\n')
print(json.dumps(dict(variants=len(variants), identities=len(files))))
