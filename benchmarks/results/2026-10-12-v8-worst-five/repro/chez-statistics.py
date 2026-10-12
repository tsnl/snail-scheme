#!/usr/bin/env python3
"""Run statistics around the already frozen safe-level-2 Chez programs."""

import importlib.util
import json
from pathlib import Path


# ---- Reuse the frozen matrix and output checks ----


ROOT = next(parent for parent in Path(__file__).resolve().parents
            if (parent / 'benchmarks/r7rs.py').is_file())
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('profiles', HERE / 'profile-five.py')
profiles = importlib.util.module_from_spec(spec)
spec.loader.exec_module(profiles)


def invoke(case, cpu):
    directory = profiles.OUTPUT / 'diagnostics' / case['benchmark'] / 'chez-statistics'
    directory.mkdir(parents=True, exist_ok=True)
    source = Path(case['directory'])
    command = ['taskset', '-c', str(cpu), case['command'][0], '--script',
               str(HERE / 'chez-statistics.ss'), str(source / 'program.so'), str(source / 'input.txt')]
    result = profiles.r7rs.execute(command, case['directory'], 90)
    (directory / 'stdout.txt').write_text(result.pop('stdout'))
    (directory / 'stderr.txt').write_text(result.pop('stderr'))
    output = (directory / 'stdout.txt').read_text()
    result.update(command=command, artifact_sha256=profiles.digest(source / 'program.so'),
                  scope='Full invocation inside load including initialization and checking; diagnostic only.')
    if result['status'] == 'ok':
        result.update(profiles.r7rs.parse_result(output, 'chez', case['benchmark']))
        row = next(line.removeprefix('+!CHEZ-STATS!+') for line in output.splitlines()
                   if line.startswith('+!CHEZ-STATS!+'))
        result['statistics'] = json.loads(row)
        if case['benchmark'] == 'cat':
            result['cat_bytes_check'] = profiles.cat_check(case)
    (directory / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    if result['status'] != 'ok':
        raise RuntimeError('Chez diagnostic failed: ' + str(directory))
    return result


def main():
    report = json.loads((profiles.OUTPUT / 'results.json').read_text())
    rows = {case['benchmark']: invoke(case, report['cpu']) for case in report['cases']
            if case['system'] == 'chez'}
    (profiles.OUTPUT / 'chez-statistics.json').write_text(json.dumps(rows, indent=2) + '\n')


if __name__ == '__main__':
    main()
