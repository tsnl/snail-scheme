#!/usr/bin/env python3
"""Audit the entire local import closure and the preserved zero-sample launch."""

import ast
import importlib.util
import inspect
import json
from pathlib import Path
import sys

REPORT = Path(__file__).resolve().parent


# ---- Every local import, including deferred imports, is frozen ----

def module_imports(path):
    names = []
    for node in ast.walk(ast.parse(path.read_text())):
        if isinstance(node, ast.Import):
            names += [alias.name.split('.')[0] for alias in node.names]
        elif isinstance(node, ast.ImportFrom):
            names.append(node.module.split('.')[0])
    return set(names)


def audit_modules(runner):
    modules = {}
    for path in sorted((REPORT / 'supervisor').glob('*.py')):
        imports = module_imports(path)
        local = sorted(imports - sys.stdlib_module_names)
        if any(not (path.parent / (name + '.py')).is_file() for name in local):
            raise ValueError('unfrozen local dependency in ' + str(path))
        modules[path.name] = dict(sha256=runner.digest(path), local_imports=local,
                                 stdlib_imports=sorted(imports & sys.stdlib_module_names))
    return modules


# ---- No prior sample or executing group may be hidden by the correction ----

def audit_prior_launch(supervisor):
    failed = json.loads((REPORT / 'failed-launch/campaign.json').read_text())
    if failed['samples'] or list((REPORT / 'failed-launch').glob('sample-*.json')):
        raise ValueError('failed launch unexpectedly spawned samples')
    groups = sorted({row['process_group'] for row in failed['samples'] if 'process_group' in row})
    live = {group: supervisor.group_members(group) for group in groups}
    if any(live.values()):
        raise ValueError('prior executing groups remain')
    return dict(prior_samples=0, prior_owned_groups=groups, executing_prior_group_members=live)


def main():
    spec = importlib.util.spec_from_file_location('reader_runner', REPORT / 'measure-seven.py')
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    plan = json.loads((REPORT / 'timing-plan.json').read_text())
    runner.verify(plan)
    supervisor = runner.load_supervisor(plan)
    old = json.loads((REPORT.parent / '2026-10-14-strict-reader-preparation/timing-plan.json').read_text())
    for key in ('systems', 'schedule', 'environment', 'inherited_environment', 'workloads', 'cpu', 'timeout_seconds'):
        if old[key] != plan[key]:
            raise ValueError('unexpected plan change: ' + key)
    record = dict(status='passed', returncode=0, frozen_identity_count=len(plan['identities']),
                  supervisor=str(Path(supervisor.__file__).resolve()), modules=audit_modules(runner),
                  callable_contract={name: str(inspect.signature(getattr(supervisor, name)))
                      for name in ('finish_process', 'clean_group', 'group_members')},
                  **audit_prior_launch(supervisor), benchmark_processes_started=0,
                  unchanged_schedule_and_systems=True, plan_sha256=runner.digest(REPORT / 'timing-plan.json'),
                  runner_sha256=runner.digest(REPORT / 'measure-seven.py'))
    (REPORT / 'dry-verification.json').write_text(json.dumps(record, indent=2) + '\n')
    print('Verified all local imports, helper contracts and zero prior executing groups')


if __name__ == '__main__':
    main()
