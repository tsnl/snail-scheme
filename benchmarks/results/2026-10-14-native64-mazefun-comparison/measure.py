"""Compare current native64 and V8 on the same optimized full Mazefun program."""

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
REPORT = Path(__file__).resolve().parent
BUILD = ROOT / 'build/native-mazefun'
OUTPUT = BUILD / 'measurements'
NODE = '/nix/store/lfaydgacdyngci7p60s8wwvgdm74fjkx-nodejs-24.19.0/bin/node'
TASKSET = '/run/current-system/sw/bin/taskset'
REMOVED = ['NODE_OPTIONS', 'NODE_V8_COVERAGE', 'NODE_DEBUG', 'NODE_DEBUG_NATIVE', 'SNAIL_ARTIFACT_ROOT']
ENVIRONMENT = {key: value for key, value in os.environ.items()
               if key not in REMOVED and not key.startswith(('SNAIL_GC_', 'SNAIL_NATIVE_', 'SNAIL_MAZEFUN_'))}


# ---- Frozen sources, artifacts and exact invocation contract ----


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
    return {'v8': [NODE, '--no-warnings', str(BUILD / 'input/host.mjs'),
                   str(BUILD / 'common.wasm'), str(BUILD / 'input/spec.json')],
            'native': [str(BUILD / 'mazefun-native')]}


def contract():
    spec = load(BUILD / 'input/spec.json')
    assert spec['name'] == 'mazefun' and spec['count'] == 10000 and spec['inputs'] == [11, 11]
    assert spec['result_kind'] == 'i64-list-values' and len(spec['expected']) == 134
    assert spec['expected'][:2] == [2, 11] and not spec.get('trace')
    assert load(BUILD / 'correctness.json')['passed']
    assert load(BUILD / 'diagnostics.json')['passed']
    return spec


def frozen_inputs(generation):
    evidence = load(generation / 'build.json')
    paths = [Path(path) for path in evidence['sha256']]
    for path in paths:
        assert identity(path)['sha256'] == evidence['sha256'][str(path)], str(path)
    paths += [path for path in generation.iterdir() if path.is_file()]
    paths += [path for path in (BUILD / 'input').iterdir() if path.is_file()]
    paths += [path for path in BUILD.iterdir() if path.is_file()]
    paths += [path for path in REPORT.iterdir() if path.suffix in ('.c', '.h', '.py')]
    provenance = load(BUILD / 'input/provenance.json')
    preparation = Path(provenance['preparation'])
    paths += [preparation / 'compiler-source' / path for path in provenance['compiler_files']]
    paths += [preparation / 'mazefun' / path for path in provenance['case_hashes']]
    paths += [preparation / 'prepared.json', preparation / 'host.mjs', Path(NODE), Path(TASKSET)]
    paths += [Path(path) for path in load(BUILD / 'build-result.json')['environment'].values() if path.startswith('/')]
    return [identity(path) for path in sorted(set(paths))]


def prepare():
    assert not (OUTPUT / 'freeze.json').exists(), 'Preserve the previous frozen campaign.'
    generation, = BUILD.glob('mazefun-native.native-*')
    frozen = dict(spec=contract(), commands=commands(), source_commit='37e66db9e0e8315e75d4d81844e02ba5d462346b',
                  native_generation=str(generation), identities=frozen_inputs(generation))
    save(OUTPUT / 'freeze.json', frozen)
    print('frozen', len(frozen['identities']), 'files', flush=True)


# ---- Fresh processes and retained raw outcomes ----


def execute(command, cwd):
    try:
        process = subprocess.run(command, cwd=cwd, env=ENVIRONMENT, capture_output=True, text=True, timeout=900)
        return dict(returncode=process.returncode, stdout=process.stdout, stderr=process.stderr)
    except OSError as error:
        return dict(returncode=None, launch_failure=repr(error), stdout='', stderr='')
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
    assert result['result'] == '1'
    if item['variant'] == 'v8':
        assert result['barriers'] is None and result['setup_barriers'] is None
    seconds = result['seconds']
    assert type(seconds) in (int, float) and math.isfinite(seconds) and seconds > 0
    item['workload_seconds'] = seconds
    item['valid'] = True


# ---- One excluded pair, four alternating retained pairs, no replacements ----


def run_rounds(frozen, record):
    names = list(frozen['commands'])
    for round_index in range(-1, 4):
        order = names if round_index < 0 or round_index % 2 == 0 else list(reversed(names))
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
        assert len(selected) == 4 and all(item['valid'] for item in selected)
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
                  removed_prefixes=['SNAIL_GC_', 'SNAIL_NATIVE_', 'SNAIL_MAZEFUN_'], observations=[], complete=False)
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
