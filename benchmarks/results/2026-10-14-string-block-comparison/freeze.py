"""Freeze the Unicode block-storage experiment and original workload references."""

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PREP = Path('/tmp/snail-gc-string-block-preparation-20261014')
RUST = Path('/tmp/snail-rust-string-controls-20261014/build/rust-string-controls/timing-handoff/handoff.json')
CHEZ = '/nix/store/bzqpmy5kmvf0xn4xh5ixzkw00w9srh07-chez-scheme-10.4.1/bin/scheme'
TASKSET = '/run/current-system/sw/bin/taskset'
files = {str(Path(__file__).resolve()), str(ROOT / 'measure-storage.py'), str(RUST), CHEZ, TASKSET}


def load(path):
    return json.loads(Path(path).read_text())


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def verify(path, expected):
    assert digest(path) == expected, path
    files.add(str(path))


# ---- Every baseline/candidate input and source file is frozen ----

handoff = load(PREP / 'handoff.json')
proof = load(PREP / 'source-comparison.json')
assert proof['compiler_differences'] == ['src/snail-scheme/strict-wasm.sld']
files.update(str(PREP / name) for name in ['handoff.json', 'source-comparison.json'])
for label in ['baseline', 'candidate']:
    manifest_path = PREP / (label + '-manifest.json')
    verify(manifest_path, handoff[label + '_manifest_sha256'])
    for leaf, expected in load(manifest_path)['files'].items():
        verify(PREP / label / leaf, expected)
    for leaf, expected in handoff['canonical_artifacts'][label].items():
        verify(PREP / label / 'string' / leaf, expected)
    for leaf, expected in proof['shared_files'].items():
        verify(PREP / label / leaf, expected)
spec = load(PREP / 'candidate/string/spec.json')
assert spec['count'] == 100 and spec['inputs'] == [500000, 2, 524278] and spec['expected'] == 1
rust = load(RUST)
node = rust['cases'][0]['command'][0]
files.update([node, str(rust['build_provenance'])])
variants = []
for label in ['baseline', 'candidate']:
    directory = PREP / label
    variants.append(dict(name='gc-' + label, kind='json', expected='1',
        command=[node, str(directory / 'host.mjs'), str(directory / 'string/strict.wasm'),
                 str(directory / 'string/spec.json')], cwd=str(directory / 'string'), environment={}, stdin=None))


# ---- Original Chez and the two previously validated Rust references ----

variants.append(dict(name='original-chez', kind='csv', expected=None, csv_system='chez',
    csv_case='string:500000:100', command=[CHEZ, '--program', str(PREP / 'baseline/string/program.so')],
    cwd=str(PREP / 'baseline/string'), environment={}, stdin='100\n500000\n524278\n'))
for case in rust['cases']:
    if case['name'] not in ['string', 'string-u32-zeroed']:
        continue
    assert case['input_text'] == '100\n500000\n524278\n' and '--audit' not in case['command']
    for field, hash_field in [('artifact', 'wasm_sha256'), ('host', 'host_sha256'),
                             ('stdin', 'input_sha256'), ('module_source', 'module_source_sha256')]:
        verify(case[field], case[hash_field])
    for leaf, expected in case['source_bundle_hashes'].items():
        verify(Path(case['exact_source_bundle']) / leaf, expected)
    for leaf, expected in case.get('dependency_source_hashes', {}).items():
        verify(Path(case['dependency_source_root']) / leaf, expected)
    verify(case['correctness']['report'], case['correctness']['report_sha256'])
    assert case['correctness']['full_canonical_pass'] and case['correctness']['all_case_checks_pass']
    variants.append(dict(name='rust-original' if case['name'] == 'string' else 'rust-u32-zeroed',
        kind='csv', expected=case['correctness']['expected_stdout_result'],
        csv_case=case['correctness']['csv_case'], command=case['command'], cwd=case['cwd'],
        environment={}, stdin=case['input_text']))
assert len(variants) == 5
plan = dict(name='string-blocks', variants=variants, cpu=5, taskset=TASKSET, rounds=5,
            files=sorted(files), identities=[dict(path=path, sha256=digest(path)) for path in sorted(files)],
            protocol='Original 100 by ten-trial workload, threshold500000/result524278. One discarded round and five retained cyclic rotations, all fresh processes. No diagnostic or audit flags.')
(ROOT / 'string-blocks-plan.json').write_text(json.dumps(plan, indent=2) + '\n')
print(json.dumps(dict(variants=len(variants), identities=len(files))))
