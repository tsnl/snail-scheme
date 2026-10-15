from pathlib import Path
from collections import defaultdict
import hashlib
import json
import math
import re
import statistics

root = Path('/tmp/snail-boyer-measurement-20261014')
report = root / 'benchmarks/results/2026-10-14-strict-boyer-comparison'
raw = root / 'build/boyer-clean-a707974'
plan_bytes = (report / 'timing-plan.json').read_bytes()
plan = json.loads(plan_bytes)
campaign = json.loads((raw / 'campaign.json').read_text())
digest = hashlib.sha256(plan_bytes).hexdigest()
assert digest == 'b650443ae4e2069340561cda8937da9b7416c06090ea02f5b9f5adee751d6773'
assert campaign['plan_sha256'] == digest and campaign['complete'] is True
assert campaign['diagnostic_only'] is False
assert len(campaign['samples']) == len(plan['schedule']) == 112
assert len(list(raw.glob('sample-*'))) == 112
groups = defaultdict(list)
positions = defaultdict(list)
warmups = defaultdict(int)
captures = {}
for expected, stored in zip(plan['schedule'], campaign['samples']):
    directory = raw / f"sample-{expected['index']:03d}"
    row = json.loads((directory / 'record.json').read_text())
    assert row == stored
    for key, value in expected.items():
        assert row[key] == value, (expected['index'], key)
    config = plan['configurations'][row['benchmark']][row['system']]
    for key in ['command', 'cwd', 'stdin', 'dependencies']:
        assert row[key] == config[key]
    assert row['environment'] == plan['environment']
    assert row['inherited_environment'] == plan['inherited_environment']
    assert row['status'] == 'valid' and row['returncode'] == 0
    assert row['termination'] == {'exit_status': 0, 'signal': None}
    assert not row['timeout'] and not row['interrupted']
    assert not row['executing_descendants'] and not row['cleanup']['live_members']
    assert row['cleanup']['leader_reaped'] and row['capture_complete']
    assert row['capture_handles_closed'] and row['stop_signal'] is None
    for stream in ['stdout', 'stderr']:
        data = (directory / f'{stream}.bin').read_bytes()
        info = row['captures'][stream]
        assert len(data) == info['bytes']
        assert hashlib.sha256(data).hexdigest() == info['sha256']
        captures[f"{row['index']}:{stream}"] = info['sha256']
    assert (directory / 'stderr.bin').read_bytes() == b''
    stdout = (directory / 'stdout.bin').read_text()
    system, benchmark = row['system'], row['benchmark']
    if system.startswith('snail-'):
        result = json.loads(stdout)
        assert stdout.count('\n') == 1 and type(result['result']) is int
        assert result['result'] == 1
        if system == 'snail-native64':
            assert {k: v for k, v in result.items() if k != 'seconds'} == {
                'result': 1, 'barriers': 0, 'setup_closed': 1, 'worker_closed': 0, 'closed': 1}
        else:
            assert set(result) == {'result', 'seconds'}
        seconds = result['seconds']
    elif system.startswith('chez'):
        pattern = (rf'Running {benchmark}:5:1\nElapsed time: ([0-9.]+) seconds '
                   rf'\([0-9.]+\) for {benchmark}:5:1\n'
                   rf'\+!CSVLINE!\+chez,{benchmark}:5:1,([0-9.]+)\n')
        match = re.fullmatch(pattern, stdout)
        assert match and match[1] == match[2]
        seconds = float(match[2])
    else:
        match = re.fullmatch(rf'Result: 51507739\n\+!CSVLINE!\+rust-wasm,{benchmark}:1,([0-9.]+)\n', stdout)
        assert match
        seconds = float(match[1])
    assert math.isfinite(seconds) and seconds > 0
    assert seconds == row['workload_seconds']
    key = (benchmark, system)
    if row['phase'] == 'measurement':
        groups[key].append(seconds)
        positions[key].append(row['position'])
    else:
        assert row['phase'] == 'discarded-warmup'
        warmups[key] += 1

summary = {}
for (benchmark, system), values in groups.items():
    assert len(values) == 7 and warmups[(benchmark, system)] == 1
    assert sorted(positions[(benchmark, system)]) == list(range(7))
    computed = dict(samples=7, median=statistics.median(values), range=[min(values), max(values)])
    assert computed == campaign['summary'][benchmark]['systems'][system]
    summary[f'{benchmark}/{system}'] = computed
assert len(summary) == 14
for name, expected in plan['identities'].items():
    path = Path(name)
    if not path.is_absolute():
        path = root / path
    with path.open('rb') as stream:
        actual = hashlib.file_digest(stream, 'sha256').hexdigest()
    assert actual == expected, name
result = dict(plan_sha256=digest, raw_records=112, warmups=14, retained=98,
              identities_verified=len(plan['identities']), captures=captures, summaries=summary,
              scope='Independent parent parser; no measurement/reviewer imports or guest execution. Checks raw result frames, command/settings identity, terminal/cleanup records, exact schedule, balanced retained positions, every median/range and all frozen file hashes. Does not independently establish process-group coverage beyond recorded evidence.')
out = Path('/tmp/snail-boyer-parent-review-20261014.json')
out.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({k: result[k] for k in ['plan_sha256', 'raw_records', 'warmups', 'retained', 'identities_verified']}))
print(out)
