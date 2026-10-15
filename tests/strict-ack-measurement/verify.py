#!/usr/bin/env python3
"""Exercise frozen Ackermann framing and ownership without timing more guests."""

import argparse
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import signal
import sys
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / 'benchmarks/results/2026-10-14-strict-ack-measurement-preparation'


# ---- Load one reviewed runner and its completed timer diagnostics ----

def load_runner():
    specification = importlib.util.spec_from_file_location('ack_measurement', REPORT / 'measure.py')
    runner = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(runner)
    return runner


def rejected(operation):
    try:
        operation()
    except (ValueError, FileExistsError):
        return True
    raise AssertionError('invalid observation was accepted')


def forbidden_process(*arguments, **keywords):
    raise AssertionError('dry verification attempted to start a process')


def clock_replacement(runner, row, text):
    match = runner.re.fullmatch(runner.output_pattern(row['system']), row['stdout'])
    return row['stdout'].replace(match['seconds'], text)


# ---- Exact real output frames supply the negative cases ----

def malformed_frames(runner, row):
    stdout = row['stdout']
    changed = stdout.replace('32765', '32764') if '32765' in stdout else stdout.replace('ack:3:12:2', 'ack:3:12:1')
    cases = {'wrong-result-or-complete-unit': changed, 'truncated-output': stdout[:-1],
             'duplicate-clock': stdout + stdout.splitlines()[-1] + '\n',
             'unexpected-output': stdout + 'unexpected\n'}
    for name, clock in (('nan', 'NaN'), ('infinite', 'Infinity'), ('overflow', '1e999'),
                        ('negative', '-1'), ('zero', '0'), ('underflow', '1e-999')):
        cases[name + '-clock'] = clock_replacement(runner, row, clock)
    return cases


def verify_frames(runner, rows):
    results = []
    for row in rows:
        assert runner.workload_seconds(row['system'], row) == row['workload_seconds']
        for name, stdout in malformed_frames(runner, row).items():
            invalid = dict(row, stdout=stdout)
            rejected(lambda: runner.workload_seconds(row['system'], invalid))
            results.append(dict(system=row['system'], case=name, stdout=stdout, rejected=True))
    return results


def verify_process_rejections(runner, row):
    cases = {'unsuccessful-exit': dict(returncode=7), 'stderr': dict(stderr='unexpected'),
             'timeout': dict(timeout=True), 'live-descendant': dict(executing_descendants=[12345]),
             'live-cleanup-member': dict(cleanup=dict(row['cleanup'], live_members=[12345])),
             'zero-process-clock': dict(process_seconds=0),
             'nonfinite-process-clock': dict(process_seconds=float('inf'))}
    for changes in cases.values():
        rejected(lambda: runner.workload_seconds(row['system'], dict(row, **changes)))
    return list(cases)


# ---- Default verification and changed plans start no child ----

def verify_dry_path(runner, plan):
    transcript = io.StringIO()
    with patch.object(runner.subprocess, 'Popen', forbidden_process):
        with patch.object(sys, 'argv', [str(REPORT / 'measure.py')]), contextlib.redirect_stdout(transcript):
            runner.main()
        existing = REPORT / 'timer-diagnostics'
        before = runner.digest(existing / 'campaign.json')
        rejected(lambda: runner.execute(plan, existing, True))
        assert runner.digest(existing / 'campaign.json') == before
    assert transcript.getvalue() == 'Verified fixed schedule, identities and supervisor imports; no guest started\n'
    return dict(guest_processes_started=0, transcript=transcript.getvalue(), existing_campaign_preserved=True)


def verify_identity_guards(runner, plan):
    invalid = copy.deepcopy(plan)
    invalid['identities'][str(REPORT / 'measure.py')] = '0' * 64
    with patch.object(runner.subprocess, 'Popen', forbidden_process):
        rejected(lambda: runner.verify(invalid))
        invalid = copy.deepcopy(plan)
        invalid['schedule'][0]['retained'] = True
        rejected(lambda: runner.verify(invalid))
        invalid = copy.deepcopy(plan)
        invalid['systems']['production-v8']['command'].append('--stack-size=4096')
        rejected(lambda: runner.verify(invalid))
    return ['changed-runner', 'changed-retention', 'changed-command']


# ---- Four real process groups exercise the unchanged ownership operation ----

def owned_fixture(runner, plan, supervisor, output, name, code, timeout=120, stop=None):
    record = dict(fixture=name, command=[plan['taskset'], '-c', str(plan['cpu']),
                  plan['python'], '-I', '-B', '-c', code], diagnostic_only=True, status='starting')
    config = dict(cwd=str(REPORT), stdin=None)
    path = output / (name + '.json')
    runner.save(path, record)
    try:
        runner.run_owned(dict(plan, timeout_seconds=timeout), config, record, path, supervisor)
        assert stop is None
    except KeyboardInterrupt as error:
        assert runner.STOP_SIGNAL == stop
        record['stop_error'] = repr(error)
    finally:
        record.update(stop_signal=runner.STOP_SIGNAL, status='recorded')
        runner.save(path, record)
    assert not record['cleanup']['live_members'] and not supervisor.group_members(record['process_group'])
    assert record['cleanup']['leader_reaped'] and record['cleanup']['capture_handles_closed']
    return record


def verify_owned_fixtures(runner, plan, output):
    supervisor = runner.load_supervisor(plan)
    failures = owned_fixture(runner, plan, supervisor, output, 'unsuccessful-exit',
                            'import sys\nprint("controlled failure")\nsys.exit(7)\n')
    assert failures['returncode'] == 7 and not failures['timeout']
    descendant = ('import os,time\npid=os.fork()\nif pid==0:\n'
                  ' os.close(0);os.close(1);os.close(2);time.sleep(60)\n'
                  'else:\n print(pid,flush=True);time.sleep(60)\n')
    timeout = owned_fixture(runner, plan, supervisor, output, 'timeout-descendant', descendant, timeout=0.2)
    assert timeout['timeout'] and int(timeout['stdout'].strip()) > 0
    rows = [failures, timeout]
    for number in (signal.SIGINT, signal.SIGTERM):
        runner.STOP_SIGNAL = None
        signal.signal(number, runner.request_stop)
        code = f'import os,signal,time\nprint("stop fixture",flush=True)\nos.kill(os.getppid(),{number})\ntime.sleep(0.05)\n'
        rows.append(owned_fixture(runner, plan, supervisor, output, signal.Signals(number).name,
                                  code, stop=number))
    runner.STOP_SIGNAL = None
    return rows


# ---- Tests ----

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    options = parser.parse_args()
    options.output.mkdir(parents=True, exist_ok=False)
    runner = load_runner()
    plan = json.loads((REPORT / 'timing-plan.json').read_text())
    diagnostic = json.loads((REPORT / 'timer-diagnostics/campaign.json').read_text())
    assert diagnostic['complete'] and diagnostic['diagnostic_only']
    assert len(diagnostic['samples']) == 7 and all(not row['retained'] for row in diagnostic['samples'])
    report = dict(passed=False, benchmark_processes_started=0, timer_diagnostic_processes_already_completed=7,
                  planned_processes=56, predetermined_discards=7, retained_processes=49,
                  plan_sha256=runner.digest(REPORT / 'timing-plan.json'), runner_sha256=runner.digest(REPORT / 'measure.py'))
    try:
        report['dry_path'] = verify_dry_path(runner, plan)
        report['identity_rejections'] = verify_identity_guards(runner, plan)
        report['complete_output_rejections'] = verify_frames(runner, diagnostic['samples'])
        report['process_record_rejections'] = verify_process_rejections(runner, diagnostic['samples'][0])
        report['owned_lifecycle_diagnostics'] = verify_owned_fixtures(runner, plan, options.output)
        runner.verify(plan)
        report.update(passed=True, all_diagnostic_handles_terminal=True)
    finally:
        runner.save(options.output / 'summary.json', report)
    print(json.dumps(dict(passed=report['passed'], invalid_frames=len(report['complete_output_rejections']),
                         ownership_processes=len(report['owned_lifecycle_diagnostics']))))


if __name__ == '__main__':
    main()
