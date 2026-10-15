"""Independently recompute the completed reader campaign, without guest runs."""

from collections import defaultdict
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import statistics

ROOT = Path('/tmp/snail-strict-reader-20261014')
DIRECTORY = ROOT / 'build/strict-reader-seven-campaign-attempt2-20261014'
OUTPUT = Path('/tmp/snail-reader-independent-review-20261014.json')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_seconds(row, workload):
    system, text = row['system'], row['stdout']
    if system.startswith('strict-'):
        data = json.loads(text)
        assert text.endswith('\n') and text.count('\n') == 1 and data['result'] == 1
        if system == 'strict-native':
            assert data['barriers'] == 0 and data['setup_closed'] == 1
            assert data['worker_closed'] == workload['count']
            assert data['closed'] == workload['count'] + 1
        return data['seconds']
    if system.startswith('chez-'):
        tag = row['benchmark'] + ':' + str(workload['count'])
        lines = text.splitlines()
        assert len(lines) == 3 and lines[0] == 'Running ' + tag
        match = re.fullmatch(r'Elapsed time: ([0-9.eE+\-]+) seconds \(([0-9.eE+\-]+)\) for ' + tag, lines[1])
        assert match and lines[2] == '+!CSVLINE!+chez,' + tag + ',' + match[1]
        return float(match[1])
    lines = text.splitlines()
    assert len(lines) == 2 and lines[0] == workload['rust_result_line']
    prefix = '+!CSVLINE!+rust-wasm,' + row['benchmark'] + ':' + str(workload['count']) + ','
    assert lines[1].startswith(prefix)
    return float(lines[1][len(prefix):])


def validate_record(index, row, plan):
    assert row == json.loads((DIRECTORY / f'sample-{index:02}.json').read_text())
    assert row['status'] == 'valid' and row['returncode'] == 0
    assert not row['timeout'] and not row['stderr'] and not row['cleanup']['live_members']
    scheduled = {key: row[key] for key in ('benchmark', 'system', 'round', 'retained')}
    assert scheduled == plan['schedule'][index]
    config = plan['systems'][row['benchmark']][row['system']]
    assert row['command'] == [plan['taskset'], '-c', str(plan['cpu']), *config['argv']]
    assert row['cwd'] == config['cwd']
    assert row['environment'] == plan['environment']
    assert row['inherited_environment'] == plan['inherited_environment']
    seconds = read_seconds(row, plan['workloads'][row['benchmark']])
    assert seconds == row['workload_seconds'] and seconds > 0


def main():
    campaign = json.loads((DIRECTORY / 'campaign.json').read_text())
    plan, rows = campaign['plan'], campaign['samples']
    assert campaign['complete'] and 'error' not in campaign and len(rows) == 112
    assert len(list(DIRECTORY.glob('sample-*.json'))) == 112
    for path, expected in plan['identities'].items():
        assert digest(path) == expected, path
    groups, positions = defaultdict(list), defaultdict(list)
    for index, row in enumerate(rows):
        validate_record(index, row, plan)
        if row['retained']:
            key = (row['benchmark'], row['system'])
            groups[key].append(row['workload_seconds'])
            positions[key].append(index % 7)
    derived = {}
    for (benchmark, system), values in groups.items():
        assert len(values) == 7 and sorted(positions[benchmark, system]) == list(range(7))
        result = dict(samples=7, workload_median=statistics.median(values), workload_range=[min(values), max(values)])
        assert all(campaign['summary'][benchmark][system][key] == value for key, value in result.items())
        derived.setdefault(benchmark, {})[system] = result
    before = json.loads((DIRECTORY / 'host-before.json').read_text())
    after = json.loads((DIRECTORY / 'host-after.json').read_text())
    policies = {key: [before['policy'][key], after['policy'][key]] for key in before['policy']}
    result = dict(reviewed_at=datetime.now(timezone.utc).isoformat(), status='passed',
                  campaign_sha256=digest(DIRECTORY / 'campaign.json'),
                  reviewer_sha256=digest(__file__), frozen_identities=len(plan['identities']),
                  samples=112, retained=98, predeclared_discards=14,
                  full_record_command_environment_framing_result_cleanup_checks=True,
                  each_system_once_at_each_retained_position=True,
                  recomputed=derived, before_after_cpu_policy=policies,
                  limitations=['Different provider linkage and representations remain; ratios do not isolate an engine or collector.',
                               'Current hashes establish artifact identity at review; campaign verification records cover its before/after checks.',
                               'Process cleanup records concern owned process groups, not unrelated host activity.'])
    OUTPUT.write_text(json.dumps(result, indent=2) + '\n')
    print('PASS: 112 records, 111 frozen identities, 98 retained samples, all medians and balanced positions')


if __name__ == '__main__':
    main()
