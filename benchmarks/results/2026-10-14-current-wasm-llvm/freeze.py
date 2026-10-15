"""Validate the archived emitter handoff and freeze a balanced measurement plan."""

import datetime
import hashlib
import json
from pathlib import Path
import subprocess


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


root = Path('/tmp/snail-current-wasm-llvm-20261014')
work = Path(__file__).resolve().parent
destination = work / 'current-wasm-llvm-comparison'
destination.mkdir(exist_ok=True)
handoff_path = root / 'build/current-wasm-llvm/handoff.json'
handoff = json.loads(handoff_path.read_text())
files = {str(handoff_path), str(Path(__file__).resolve()),
         str(work / 'measure-current-llvm.py'), '/run/current-system/sw/bin/taskset'}
cases = []
for case in handoff['cases']:
    manifest = json.loads(Path(case['manifest']).read_text())
    for path, expected in manifest['sha256'].items():
        assert digest(path) == expected, path
        files.add(path)
    for tool in manifest['tools'].values():
        assert digest(tool['path']) == tool['sha256'], tool
        files.add(tool['path'])
    native_dir = Path(case['manifest']).parent
    files.update([case['manifest'], str(native_dir / 'build.json')])
    assert digest(native_dir / 'input.wasm') == case['input_wasm_sha256']
    assert digest(manifest['source_wasm']) == case['input_wasm_sha256']
    assert digest(manifest['source_specification']) == digest(case['specification'])
    files.update([manifest['source_wasm'], manifest['source_specification']])
    variants = []
    for name, variant in case['variants'].items():
        files.add(variant['command'][0])
        variants.append(dict(variant, name=name, cwd=str(root)))
    cases.append(dict(name=case['benchmark'], expected=case['expected_result'],
                      count=case['count'], variants=variants))
plan = dict(cpu=5, taskset='/run/current-system/sw/bin/taskset', cases=cases,
            files=sorted(files), identities=[dict(path=path, sha256=digest(path)) for path in sorted(files)],
            handoff=handoff,
            experiment_revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip())
(destination / 'plan.json').write_text(json.dumps(plan, indent=2) + '\n')
quiet = dict(start_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
             cpu=5, coordination='Rust agent explicitly acknowledged CPU hold; LLVM agent completed with no commands running; Astra completed and idle. No parent build, test, profile or compression jobs during clean runs.',
             scope='Agent-controlled work is held; unrelated system activity is not excluded.',
             os=Path('/proc/version').read_text(), cpuinfo=Path('/proc/cpuinfo').read_text(),
             initial_load=Path('/proc/loadavg').read_text())
(destination / 'quiet-window.json').write_text(json.dumps(quiet, indent=2) + '\n')
print(json.dumps(dict(cases=len(cases), identities=len(files), experiment_revision=plan['experiment_revision'])))
