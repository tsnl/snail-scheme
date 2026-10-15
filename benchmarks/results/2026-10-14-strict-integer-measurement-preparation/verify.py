#!/usr/bin/env python3
"""Exercise owned cleanup and reject incomplete outputs before a quiet launch."""

import importlib.util
import json
import os
from pathlib import Path
import signal
import sys

REPORT = Path(__file__).resolve().parent


# ---- The actual frozen runner and its imports must pass the default path ----

def load_runner():
    spec = importlib.util.spec_from_file_location('integer_measurement', REPORT / 'measure.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# ---- Actual short processes cover failure, deadline, descendants and stop signals ----

def ownership_case(measure, supervisor, label, source, stop_signal=None):
    path = REPORT / 'ownership-diagnostics' / (label + '.json')
    record = dict(command=[sys.executable, '-I', '-B', '-c', source], diagnostic_only=True)
    config = dict(cwd=str(REPORT))
    try:
        measure.run_owned(dict(environment={}, timeout_seconds=0.2), config, record, path, supervisor)
    except KeyboardInterrupt as error:
        record['interrupted'] = str(error)
    finally:
        measure.STOP_SIGNAL = None
        measure.save(path, record)
    if (record['cleanup']['live_members'] or not record['cleanup']['leader_reaped']
            or not record['cleanup']['capture_handles_closed'] or supervisor.group_members(record['process_group'])):
        raise ValueError('owned process case left a handle or executing member: ' + label)
    if stop_signal and 'interrupted' not in record:
        raise ValueError('handled stop signal did not reach cleanup: ' + label)
    return record


def check_ownership(measure, supervisor):
    (REPORT / 'ownership-diagnostics').mkdir(exist_ok=True)
    fail = ownership_case(measure, supervisor, 'nonzero',
                         'import sys; print("partial"); print("error",file=sys.stderr); sys.exit(7)')
    if fail['returncode'] != 7 or fail['stdout'] != 'partial\n' or fail['stderr'] != 'error\n':
        raise ValueError('nonzero process evidence differs')
    spawn = 'import subprocess,sys,time,os,signal; child=subprocess.Popen([sys.executable,"-I","-B","-c","import time; time.sleep(60)"]); print(child.pid,flush=True); '
    rows = [fail, ownership_case(measure, supervisor, 'descendant-timeout', spawn + 'time.sleep(60)')]
    for number in (signal.SIGINT, signal.SIGTERM):
        previous = signal.signal(number, measure.request_stop)
        try:
            rows.append(ownership_case(measure, supervisor, signal.Signals(number).name.lower(),
                spawn + f'os.kill(os.getppid(),{int(number)}); time.sleep(60)', number))
        finally:
            signal.signal(number, previous)
    if any(not row['timeout'] for row in rows[1:]):
        raise ValueError('fixed process deadline was not exercised')
    return rows


# ---- Every real timer output is complete; mutations must fail strict framing ----

def reject_output(measure, plan, row, record, label, text):
    changed = {**record, 'stdout': text}
    try:
        measure.workload_seconds(plan, row, changed)
    except (ValueError, OverflowError):
        return label
    raise ValueError('malformed output was accepted: ' + label)


def check_outputs(measure, plan, diagnostics):
    if not diagnostics['complete'] or len(diagnostics['samples']) != 16 or not diagnostics['diagnostic_only']:
        raise ValueError('all sixteen frozen timer paths have not completed')
    cases = []
    for record in diagnostics['samples']:
        name, system = record['benchmark'], record['system']
        row = dict(benchmark=name, system=system)
        measure.workload_seconds(plan, row, record)
        output, clock = record['stdout'].splitlines()
        last = plan['workloads'][name]['expected'][-1]
        at = output.rfind(last)
        wrong_final = output[:at] + str(int(last) + 1) + output[at + len(last):]
        mutations = {'wrong-final-component': wrong_final + '\n' + clock + '\n',
                     'truncated-numerical-output': output[:-2] + '\n' + clock + '\n',
                     'duplicate-clock': record['stdout'] + clock + '\n',
                     'unexpected-output': 'extra\n' + record['stdout']}
        mutations.update({label: output + '\n' + clock.rsplit(',', 1)[0] + ',' + value + '\n'
                          for label, value in [('nan-clock', 'NaN'), ('infinite-clock', '1e9999'), ('negative-clock', '-1')]})
        cases.append(dict(benchmark=name, system=system, rejected=[
            reject_output(measure, plan, row, record, label, text) for label, text in mutations.items()]))
    return cases


def main():
    measure = load_runner()
    plan = json.loads((REPORT / 'timing-plan.json').read_text())
    measure.verify(plan)
    measure.verify_import_closure(plan)
    supervisor = measure.load_supervisor(plan)
    ownership = check_ownership(measure, supervisor)
    diagnostics = json.loads((REPORT / 'timer-diagnostics-final/campaign.json').read_text())
    outputs = check_outputs(measure, plan, diagnostics)
    groups = [row['process_group'] for row in ownership + diagnostics['samples']]
    if any(supervisor.group_members(group) for group in groups):
        raise ValueError('a diagnostic owned group remains executing')
    measure.save(REPORT / 'dry-verification.json', dict(passed=True, benchmark_processes_started=0,
        timer_diagnostic_processes_already_completed=16, owned_lifecycle_diagnostic_processes=len(ownership),
        planned_processes=144, retained_processes=128, prediscard_processes=16,
        imported_supervisor=str(Path(supervisor.__file__).resolve()), identities=len(plan['identities']),
        plan_sha256=measure.digest(REPORT / 'timing-plan.json'), runner_sha256=measure.digest(REPORT / 'measure.py'),
        exact_commands_match_original=True, complete_output_rejections=outputs,
        all_diagnostic_handles_terminal=True, owned_groups=groups))
    print('Dry verification passed: imports, exact commands, full framing and owned process cleanup')


if __name__ == '__main__':
    main()
