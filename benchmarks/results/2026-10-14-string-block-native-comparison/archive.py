"""Preserve the completed four-cell String comparison without rerunning timing."""

import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import stat
import statistics
import subprocess
import tarfile

REPORT = Path(__file__).resolve().parent
RAW = Path('/tmp/snail-strict-lattice-measurement-20261014/build')
PREP = Path('/tmp/snail-gc-string-block-preparation-20261014')
NATIVE_ROOTS = [Path('/tmp/snail-current-wasm-llvm-20261014'),
                Path('/tmp/snail-native-string-blocks-20261014')]
NATIVE_DIRS = [NATIVE_ROOTS[0] / 'build/current-wasm-llvm/string',
               NATIVE_ROOTS[1] / 'build/string-blocks']
NATIVE_COMMIT = 'b419cc607e6cc13e854671fb9796f894a9d1faa6'


# ---- Verify raw observations, complete rotation and unchanged identities ----


def load(path):
    return json.loads(path.read_text())


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


record = load(RAW / 'string-native-clean.json')
plan = load(RAW / 'string-native-plan.json')
assert record['complete'] and record['plan'] == plan and len(record['observations']) == 20
assert record['identities_before'] == record['identities_after'] == plan['identities']
assert len(plan['identities']) == 689 and plan['rounds'] == len(plan['variants']) == 4
assert plan['files'] == [item['path'] for item in plan['identities']]
for item in plan['identities']:
    assert digest(Path(item['path'])) == item['sha256'], item
for number in range(-1, 4):
    observations = [item for item in record['observations'] if item['round'] == number]
    shift = max(number, 0)
    order = plan['variants'][shift:] + plan['variants'][:shift]
    assert [item['variant'] for item in observations] == [item['name'] for item in order]
    for item in observations:
        result = json.loads(item['stdout'])
        assert item['returncode'] == 0 and not item['stderr'] and result['result'] == '1'
        assert result['barriers'] is None and result['setup_barriers'] is None
        assert item['retained'] == (number >= 0)
        assert math.isfinite(item['workload_seconds']) and item['workload_seconds'] > 0
        assert result['seconds'] == item['workload_seconds']
        assert '--validate' not in item['command']
for source, name in [('string-native-clean.json', 'clean.json'), ('string-native-plan.json', 'plan.json'),
                     ('string-native-quiet-window.json', 'quiet-window.json'), ('measure-storage.py', 'measure.py')]:
    shutil.copy2(RAW / source, REPORT / name)


# ---- Native build sources, matched Wasm and tool provenance ----


files = {Path(path) for path in plan['files'] if not path.startswith(('/nix/', '/run/'))}
external_tools = {item['path']: item['sha256'] for item in plan['identities']
                  if item['path'].startswith(('/nix/', '/run/'))}
manifests = [load(directory / 'manifest.json') for directory in NATIVE_DIRS]
for root, directory, manifest in zip(NATIVE_ROOTS, NATIVE_DIRS, manifests):
    assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip() == NATIVE_COMMIT
    files.update(path for path in directory.iterdir() if path.is_file())
    for path, expected in manifest['sha256'].items():
        assert digest(Path(path)) == expected, path
        files.add(Path(path))
    for tool in manifest['tools'].values():
        assert digest(Path(tool['path'])) == tool['sha256'], tool
        external_tools[tool['path']] = tool['sha256']
    supporting = root / 'benchmarks/results/2026-10-14-current-wasm-llvm'
    files.update(supporting / name for name in ['checks.json', 'full-validation.json',
                 'final-harness-validation.json', 'tools.json'])
source_names = ['src/native.c', 'src/precise-gc.c', 'src/precise-gc.h',
                'src/snail-scheme/llvm.sld', 'src/snail-scheme/wasm-read.sld',
                'src/snail-scheme/wasm-resolve.sld', 'src/snail-scheme/llvmlite.sld',
                'experiments/current-wasm-llvm/prepare.py', 'experiments/current-wasm-llvm/host.c',
                'experiments/current-wasm-llvm/translate.scm', 'experiments/current-wasm-llvm/node-host.mjs']
for name in source_names:
    assert (NATIVE_ROOTS[0] / name).read_bytes() == (NATIVE_ROOTS[1] / name).read_bytes(), name
matched = []
for layout, label, directory in zip(['flat', 'blocks'], ['baseline', 'candidate'], NATIVE_DIRS):
    wasm = PREP / label / 'string/strict.wasm'
    assert wasm.read_bytes() == (directory / 'input.wasm').read_bytes()
    assert (PREP / label / 'string/spec.json').read_bytes() == (directory / 'spec.json').read_bytes()
    spec = load(directory / 'spec.json')
    assert spec['count'] == 100 and spec['inputs'] == [500000, 2, 524278] and spec['expected'] == 1
    matched.append(dict(layout=layout, wasm_sha256=digest(wasm),
                        native_sha256=digest(directory / 'native'), native_directory=str(directory)))
node = plan['variants'][0]['command'][0]
env = {key: value for key, value in os.environ.items() if key != 'NODE_OPTIONS'}
versions = subprocess.check_output([node, '-p', 'JSON.stringify(process.versions)'], env=env, text=True)
process_summary = {}
for variant in plan['variants']:
    observations = [item for item in record['observations'] if item['retained'] and item['variant'] == variant['name']]
    samples = [item['workload_seconds'] for item in observations]
    assert record['summary'][variant['name']]['median'] == statistics.median(samples)
    process_summary[variant['name']] = dict(process_median=statistics.median(item['process_seconds'] for item in observations),
        setup_median=statistics.median(item['guest_report']['setup_seconds'] for item in observations) if variant['name'].startswith('native-') else None)
provenance = dict(native_commit=NATIVE_COMMIT, strict_block_commit=load(PREP / 'handoff.json')['compiler_commit'],
    matched_wasm=matched, unchanged_native_sources={name: digest(NATIVE_ROOTS[0] / name) for name in source_names},
    native_build_manifests=[str(directory / 'manifest.json') for directory in NATIVE_DIRS],
    external_tools=external_tools, node_versions=json.loads(versions),
    workload_summary=record['summary'], process_summary=process_summary,
    native_environment={'SNAIL_GC_HEAP_BYTES': '314572800'},
    timing='Initialization and prefaulting precede bench(count); final acceptance assertion is timed; formatting and diagnostics follow.',
    archive_scope='Every frozen identity except external Nix/run binaries, plus bounded relevant native String build/validation evidence.')
save(REPORT / 'provenance.json', provenance)
files.update(PREP / name for name in ['final-checks.json', 'retention-inspection.json', 'prepare-candidate.py'])
files.update(REPORT / name for name in ['README.md', 'clean.json', 'plan.json', 'quiet-window.json',
             'measure.py', 'archive.py', 'replay.py', 'provenance.json'])


# ---- Preserve original path mappings and modes in a bounded regular-file archive ----


mapping = {str(path): 'files/' + str(path).lstrip('/') for path in sorted(files)}
save(REPORT / 'path-map.json', mapping)
hashes, modes = {}, {}
archive_path = REPORT / 'artifacts.tar.xz'
with tarfile.open(archive_path, 'w:xz') as archive:
    for path in sorted(files):
        assert path.is_file() and not path.is_symlink(), path
        member = mapping[str(path)]
        info = archive.gettarinfo(str(path), arcname=member)
        info.uid = info.gid = info.mtime = 0
        info.uname = info.gname = ''
        hashes[member] = digest(path)
        modes[member] = stat.S_IMODE(path.stat().st_mode)
        with path.open('rb') as source:
            archive.addfile(info, source)
        assert digest(path) == hashes[member], path
    path = REPORT / 'path-map.json'
    info = archive.gettarinfo(str(path), arcname='path-map.json')
    info.uid = info.gid = info.mtime = 0
    info.uname = info.gname = ''
    with path.open('rb') as source:
        archive.addfile(info, source)
    hashes['path-map.json'] = digest(path)
    modes['path-map.json'] = stat.S_IMODE(path.stat().st_mode)
save(REPORT / 'manifest.json', dict(archive_sha256=digest(archive_path), files=hashes, modes=modes,
    frozen_identities=len(plan['identities']), archived_frozen_identities=686,
    external_tools=external_tools, archive_bytes=archive_path.stat().st_size))
print(json.dumps(dict(archive_sha256=digest(archive_path), files=len(hashes), archive_bytes=archive_path.stat().st_size)))
