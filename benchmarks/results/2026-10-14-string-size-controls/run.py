"""Execute the six frozen parameter controls sequentially in one quiet window."""

import datetime
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
DIRECTORY = ROOT / 'build/size-controls'
inventory = json.loads((DIRECTORY / 'inventory.json').read_text())
assert len(inventory) == 6
for item in inventory:
    plan = Path(item['plan'])
    output = plan.parent / 'clean.json'
    subprocess.run([sys.executable, str(ROOT / 'build/measure-sizes.py'),
                    str(plan), str(output)], check=True)
    result = json.loads(output.read_text())
    assert result['complete'] and len(result['observations']) == 10
    assert result['identities_before'] == result['identities_after']
    print(item['threshold'], json.dumps(result['summary']), flush=True)
window = DIRECTORY / 'quiet-window.json'
record = json.loads(window.read_text())
record.update(finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
              all_clean_results_pass=True, total_executions=60)
window.write_text(json.dumps(record, indent=2) + '\n')
