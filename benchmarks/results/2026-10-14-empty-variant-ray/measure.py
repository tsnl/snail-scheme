"""Measure empty-constructor sharing on full Ray, independently on V8 and native."""

import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
BUILD = ROOT / 'build/empty-variants'
OUTPUT = BUILD / 'measurements'
NODE = '/nix/store/lfaydgacdyngci7p60s8wwvgdm74fjkx-nodejs-24.19.0/bin/node'
TASKSET = '/run/current-system/sw/bin/taskset'
REMOVED = ['NODE_OPTIONS', 'NODE_V8_COVERAGE', 'NODE_DEBUG', 'NODE_DEBUG_NATIVE', 'SNAIL_ARTIFACT_ROOT']
ENVIRONMENT = {key: value for key, value in os.environ.items()
               if key not in REMOVED and not key.startswith(('SNAIL_GC_', 'SNAIL_NATIVE_'))}


# ---- Frozen inputs and the unchanged complete workload ----


def load(path):
    return json.loads(Path(path).read_text())


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n')


def identity(path):
    return dict(path=str(path), sha256=hashlib.sha256(Path(path).read_bytes()).hexdigest())


def verify(identities):
    for expected in identities:
        assert identity(expected['path']) == expected, expected['path']


def commands():
    result = {}
    for variant in ['baseline', 'candidate']:
        result[variant + '-v8'] = [NODE, '--no-warnings', str(BUILD / 'input/ray-host.mjs'),
                                  str(BUILD / variant / 'v8.wasm'), str(BUILD / 'input/spec.json')]
        result[variant + '-native'] = [str(BUILD / variant / 'native')]
    return result


def contract():
    spec = load(BUILD / 'input/spec.json')
    assert spec['count'] == 50 and spec['inputs'] == [1, 1] and spec['expected'] == 1
    assert spec['pathname'] == 'outputs/ray.output' and not spec.get('trace')
    checks = load(BUILD / 'correctness.json')
    assert {(item['variant'], item['target']) for item in checks} == {
        (variant, target) for variant in ['baseline', 'candidate'] for target in ['v8', 'native']}
    assert len(checks) == 4 and all(item['passed'] for item in checks)
    return spec


def frozen_inputs():
    paths = {Path(__file__).resolve(), Path(NODE), Path(TASKSET),
             BUILD / 'correctness.json', BUILD / 'source-comparison.json'}
    paths.update(path for path in (BUILD / 'input').rglob('*') if path.is_file())
    for variant in ['baseline', 'candidate']:
        directory = BUILD / variant
        generation, = directory.glob('native.native-*')
        evidence = load(generation / 'build.json')
        for path, digest in evidence['sha256'].items():
            assert identity(path)['sha256'] == digest, path
            paths.add(Path(path))
        paths.update(path for path in directory.rglob('*') if path.is_file())
        paths.update(Path(path) for path in load(directory / 'compile.json')['environment'].values()
                     if path.startswith('/'))
        paths.update(Path(path) for path in evidence['tools'].values())
    paths.update([ROOT / 'scripts/link-strict-runtime',
                  ROOT / 'build/wasm-runtime/wasm32-wasip1/release/snail_runtime.wasm'])
    return [identity(path) for path in sorted(paths)]


def prepare():
    assert not (OUTPUT / 'freeze.json').exists(), 'Preserve the previous frozen campaign.'
    frozen = dict(spec=contract(), commands=commands(), baseline_commit='71c6cfbe4ce1fede25b598578c611bfb3951b6b8',
                  retained_cycles=8, identities=frozen_inputs())
    save(OUTPUT / 'freeze.json', frozen)
    print('frozen', len(frozen['identities']), 'files', flush=True)


# ---- Fresh processes, both clocks and complete output checks ----


def execute(command, cwd):
    try:
        process = subprocess.run(command, cwd=cwd, env=ENVIRONMENT, capture_output=True, text=True, timeout=900)
        return dict(returncode=process.returncode, stdout=process.stdout, stderr=process.stderr)
    except subprocess.TimeoutExpired as error:
        return dict(returncode=None, timeout=True, stdout=(error.stdout or b'').decode(),
                    stderr=(error.stderr or b'').decode())


def observe(variant, command, round_index, position):
    cwd = OUTPUT / 'trials' / f'round-{round_index}' / variant
    (cwd / 'outputs').mkdir(parents=True, exist_ok=False)
    arguments = [TASKSET, '-c', '5', *command]
    start = time.monotonic()
    outcome = execute(arguments, cwd)
    elapsed = time.monotonic() - start
    return dict(outcome, variant=variant, command=arguments, cwd=str(cwd), process_seconds=elapsed,
                round=round_index, position=position, retained=round_index >= 0)


def check_observation(item, spec):
    assert item['returncode'] == 0 and not item['stderr'], item
    result = json.loads(item['stdout'])
    assert result['result'] == str(spec['expected'])
    if item['variant'].endswith('-v8'):
        assert result['barriers'] is None and result['setup_barriers'] is None
    seconds = result['seconds']
    assert type(seconds) in (int, float) and math.isfinite(seconds) and seconds > 0
    item['workload_seconds'] = seconds
    image = Path(item['cwd']) / spec['pathname']
    item['image'] = dict(identity(image), bytes=image.stat().st_size)
    assert item['image']['bytes'] == 29517 and item['image']['sha256'] == spec['image_sha256']
    assert image.read_bytes() == (BUILD / 'input/expected-ray.pgm').read_bytes()
    item['valid'] = True


# ---- One excluded cycle, eight balanced retained cycles, no replacements ----


def run_rounds(frozen, record):
    names = list(frozen['commands'])
    for round_index in range(-1, frozen['retained_cycles']):
        offset = max(0, round_index) % len(names)
        order = names[offset:] + names[:offset]
        for position, variant in enumerate(order):
            item = observe(variant, frozen['commands'][variant], round_index, position)
            record['observations'].append(item)
            save(OUTPUT / 'clean.json', record)
            check_observation(item, frozen['spec'])
            save(OUTPUT / 'clean.json', record)
            print(round_index, variant, item['workload_seconds'], flush=True)


def summary(record):
    result = {}
    for variant in record['order']:
        selected = [item for item in record['observations'] if item['variant'] == variant and item['retained']]
        assert len(selected) == 8 and all(item['valid'] for item in selected)
        result[variant] = {}
        for clock in ['workload_seconds', 'process_seconds']:
            values = [item[clock] for item in selected]
            result[variant][clock] = dict(samples=values, median=statistics.median(values), min=min(values), max=max(values))
    return result


def campaign(frozen, record):
    try:
        run_rounds(frozen, record)
        verify(frozen['identities'])
        record.update(identities_unchanged=True, summary=summary(record), complete=True)
    except Exception as error:
        record['failure'] = repr(error)
        raise
    finally:
        record['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        save(OUTPUT / 'clean.json', record)


def measure():
    assert load(OUTPUT / 'quiet-window.json')['agents_holding_builds'] is True
    assert not ENVIRONMENT.get('LD_PRELOAD'), 'Injected libraries change plain execution.'
    assert not (OUTPUT / 'clean.json').exists(), 'Preserve prior outcomes; use a new campaign.'
    frozen = load(OUTPUT / 'freeze.json')
    verify(frozen['identities'])
    assert commands() == frozen['commands'] and contract() == frozen['spec']
    record = dict(started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), cpu=5,
                  order=list(frozen['commands']), removed_environment=REMOVED,
                  removed_prefixes=['SNAIL_GC_', 'SNAIL_NATIVE_'], observations=[], complete=False)
    campaign(frozen, record)
    print(json.dumps(record['summary']), flush=True)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    if sys.argv[1:] == ['prepare']:
        prepare()
    elif sys.argv[1:] == ['measure']:
        measure()
    else:
        raise SystemExit('usage: measure.py prepare | measure')


if __name__ == '__main__':
    main()
