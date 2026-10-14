"""Freeze parameter controls for the unchanged String growth workload."""

import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess


# ---- Reuse the exact previously measured programs ----

ROOT = Path(__file__).resolve().parent.parent
PREP = Path('/tmp/snail-gc-string-block-preparation-20261014')
NODE = '/nix/store/lfaydgacdyngci7p60s8wwvgdm74fjkx-nodejs-24.19.0/bin/node'
CHEZ = '/nix/store/bzqpmy5kmvf0xn4xh5ixzkw00w9srh07-chez-scheme-10.4.1/bin/scheme'
TASKSET = '/run/current-system/sw/bin/taskset'
CONTROLS = [(16, 200000), (64, 100000), (1024, 10000),
            (4096, 2500), (8192, 1250), (32768, 500)]


def load(path):
    return json.loads(path.read_text())


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def final_length(threshold):
    length = 6
    while length <= threshold:
        length = 2 * length + 10
    return length


def configuration(threshold, count):
    spec = load(PREP / 'baseline/string/spec.json')
    spec.update(count=count, original_expected=final_length(threshold))
    spec['inputs'] = [threshold, 2, spec['original_expected']]
    return spec


# ---- Record successful and deliberately incorrect expectations separately ----

def execute(command, data=None):
    env = dict(os.environ)
    env.pop('NODE_OPTIONS', None)
    p = subprocess.run(command, input=data, env=env, text=True,
                       capture_output=True, timeout=120)
    return dict(command=command, stdin=data, returncode=p.returncode,
                stdout=p.stdout, stderr=p.stderr)


def validate(directory, spec):
    small = copy.deepcopy(spec)
    small['count'] = 1
    good, bad = directory / 'count-one.json', directory / 'wrong-result.json'
    save(good, small)
    small['inputs'][2] += 1
    save(bad, small)
    results = []
    for variant in ('baseline', 'candidate'):
        command = [NODE, str(PREP / variant / 'host.mjs'),
                   str(PREP / variant / 'string/strict.wasm')]
        passed = execute([*command, str(good), '--validate'])
        failed = execute([*command, str(bad), '--validate'])
        results += [passed, failed]
        save(directory / 'validation.json', results)
        assert passed['returncode'] == 0 and not passed['stderr'], passed
        report = json.loads(passed['stdout'])
        assert report['result'] == '1' and report['barriers'] == 1
        assert failed['returncode'] != 0 and 'AssertionError' in failed['stderr'], failed
    chez = execute([CHEZ, '--program', str(PREP / 'baseline/string/program.so')],
                   f"1\n{spec['inputs'][0]}\n{spec['original_expected']}\n")
    results.append(chez)
    save(directory / 'validation.json', results)
    assert chez['returncode'] == 0 and not chez['stderr'], chez
    assert 'incorrect' not in chez['stdout'].lower() and '+!CSVLINE!+' in chez['stdout'], chez


# ---- Controls change runtime size and repeats, never the compiled source ----

def identity_files(directory):
    previous = load(Path('/tmp/snail-strict-lattice-measurement-20261014/build/string-blocks-plan.json'))
    paths = {path for path in previous['files'] if path.startswith(str(PREP))}
    paths.update([NODE, CHEZ, TASKSET, str(Path(__file__)),
                  str(ROOT / 'build/measure-sizes.py')])
    paths.update(str(path) for path in directory.iterdir() if path.is_file())
    return sorted(paths)


def freeze(directory, spec):
    variants = [dict(name=label, kind='json', expected='1',
                    command=[NODE, str(PREP / variant / 'host.mjs'),
                             str(PREP / variant / 'string/strict.wasm'),
                             str(directory / 'spec.json')],
                    cwd=str(directory), environment={}, stdin=None)
                for variant, label in [('baseline', 'flat'), ('candidate', 'blocks')]]
    paths = identity_files(directory)
    plan = dict(name=directory.name, cpu=5, taskset=TASKSET, rounds=4, variants=variants,
                files=paths, identities=[dict(path=path, sha256=digest(path)) for path in paths],
                protocol='Parameter control: unchanged String Wasm/source and ten trials; '
                         'different runtime threshold and repeat count. Four retained balanced '
                         'alternating pairs after one discarded pair. Not a canonical suite score.')
    save(directory / 'plan.json', plan)
    return dict(threshold=spec['inputs'][0], count=spec['count'],
                final_length=spec['original_expected'], plan=str(directory / 'plan.json'))


def main():
    controls = ROOT / 'build/size-controls'
    controls.mkdir(exist_ok=False)
    inventory = []
    for threshold, count in CONTROLS:
        directory = controls / str(threshold)
        directory.mkdir()
        spec = configuration(threshold, count)
        save(directory / 'spec.json', spec)
        validate(directory, spec)
        inventory.append(freeze(directory, spec))
        print(threshold, count, spec['original_expected'], 'validated and frozen', flush=True)
    save(controls / 'inventory.json', inventory)


if __name__ == '__main__':
    main()
