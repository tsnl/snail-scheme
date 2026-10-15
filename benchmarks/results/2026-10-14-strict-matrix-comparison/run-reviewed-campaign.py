"""Capture immediate policy around the one parent-released frozen campaign."""

from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / 'benchmarks/results/2026-10-14-strict-matrix-preparation'
OUTPUT = ROOT / 'build/matrix-seven-system-campaign-20261014'
BEFORE = ROOT / 'build/matrix-seven-system-campaign-before.json'
AFTER = ROOT / 'build/matrix-seven-system-campaign-after.json'
RECORD = ROOT / 'build/matrix-seven-system-campaign-launch.json'
expected = {'measure-seven.py': 'b69b2e7806684d73a8760c50a54e4e3fbeb3a770f6bb58d0190849cea7bb3da5',
            'timing-plan.json': '27ad980f6dfbae3702fd5dd20f7eda357eb3fc849a34161e80f4001ddaccddec'}
for name, sha256 in expected.items():
    if hashlib.sha256((REPORT / name).read_bytes()).hexdigest() != sha256:
        raise ValueError('reviewed freeze changed: ' + name)
if any(path.exists() for path in (OUTPUT, BEFORE, AFTER, RECORD)):
    raise ValueError('campaign evidence already exists; replacement is forbidden')
module = importlib.util.spec_from_file_location('freeze_matrix_plan', REPORT / 'freeze-plan.py')
freezer = importlib.util.module_from_spec(module)
module.loader.exec_module(freezer)
before = freezer.machine_state(5)
record = dict(parent_release='Reviewed 56-process campaign only; no replacements or concurrent heavy work.',
              release_recorded=datetime.now(timezone.utc).isoformat(), reviewed_hashes=expected,
              command=[sys.executable, str(REPORT / 'measure-seven.py'), '--run', '--output', str(OUTPUT)],
              cwd=str(ROOT), status='starting')
freezer.save(BEFORE, before)
prior = freezer.load(REPORT / 'hardware-before.json')
if before['models'] != prior['models'] or before['frequency'] != prior['frequency']:
    raise ValueError('CPU policy differs from the reviewed preparation snapshot')
freezer.save(RECORD, record)
started = time.perf_counter()
try:
    child = subprocess.Popen(record['command'], cwd=ROOT)
    record.update(status='running', runner_pid=child.pid)
    freezer.save(RECORD, record)
    record['returncode'] = child.wait()
    record['status'] = 'complete' if record['returncode'] == 0 else 'failed'
finally:
    freezer.save(AFTER, freezer.machine_state(5))
    record['process_seconds'] = time.perf_counter() - started
    record['finished'] = datetime.now(timezone.utc).isoformat()
    freezer.save(RECORD, record)
print(json.dumps(record, indent=2), flush=True)
raise SystemExit(record.get('returncode', 1))
