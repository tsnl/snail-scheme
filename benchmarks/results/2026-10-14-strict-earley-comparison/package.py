#!/usr/bin/env python3
"""Verify and package completed Earley samples without executing a benchmark."""

from collections import Counter
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import statistics
import sys
import tarfile

REPORT = Path(__file__).resolve().parent
ROOT = REPORT.parents[2]
PREPARATION = REPORT.with_name('2026-10-14-strict-earley-preparation')
RUN = ROOT / 'build/earley-clean-01'
sys.path.insert(0, str(ROOT / 'build/earley-prepare-04'))
import earley_port
module = importlib.util.spec_from_file_location('frozen_earley_runner', PREPARATION / 'measure-five.py')
runner = importlib.util.module_from_spec(module)
module.loader.exec_module(runner)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(name, value):
    (REPORT / name).write_text(json.dumps(value, indent=2) + '\n')


def check_samples(plan, campaign):
    if not campaign['complete'] or campaign['plan'] != plan or len(campaign['samples']) != 30:
        raise ValueError('campaign is incomplete or plan differs')
    for index, (scheduled, sample) in enumerate(zip(plan['schedule'], campaign['samples'])):
        if any(sample[key] != value for key, value in scheduled.items()):
            raise ValueError('sample schedule differs')
        if json.loads((RUN / f'sample-{index:02}.json').read_text()) != sample:
            raise ValueError('raw sample differs from campaign')
        if (sample['status'] != 'valid' or sample['cleanup']['live_members'] or
                sample['workload_seconds'] != runner.workload_seconds(scheduled['system'], sample)):
            raise ValueError('invalid sample result')
    retained = [sample for sample in campaign['samples'] if sample['retained']]
    balance = Counter((sample['system'], sample['position']) for sample in retained)
    if len(retained) != 25 or any(balance[(system, position)] != 1 for system in plan['systems'] for position in range(5)):
        raise ValueError('retained positions are not balanced')


def summarize(plan, campaign):
    summary = runner.summarize(campaign['samples'])
    if summary != campaign['summary']:
        raise ValueError('saved aggregate arithmetic differs')
    median = {name: row['workload_median'] for name, row in summary.items()}
    pairs = [('v8-production', 'chez-original'), ('v8-production', 'chez-adapted'),
             ('v8-common', 'v8-production'), ('native-common', 'v8-common'),
             ('native-common', 'chez-original'), ('native-common', 'chez-adapted'),
             ('chez-adapted', 'chez-original')]
    return dict(complete=True, count=1, size=15, expected=2674440, processes=30,
                discarded=5, retained=25, samples_per_system=5, systems=summary,
                time_ratios={first + '/' + second: median[first] / median[second] for first, second in pairs},
                native_heap_reservation_bytes=1073741824, rust_reference=False,
                compiler_commit=plan['compiler_commit'], implementation_commit=plan['driver_commit'],
                preparation_commit='fed3f033dda359d25fcefe04f9a281ef51d63f67',
                final_common_wasm_sha256=plan['wasm_identity']['final_common']['sha256'],
                plan_sha256=digest(PREPARATION / 'timing-plan.json'),
                runner_sha256=digest(PREPARATION / 'measure-five.py'),
                limitation='Five retained observations, overlapping V8 ranges; no isolated collector or identical-allocation claim.')


def copy_records():
    shutil.copytree(RUN, REPORT / 'measurements')
    for source, name in [('earley-clean-release.json', 'quiet-window.json'),
                         ('earley-clean-host-before.json', 'host-before.json'),
                         ('earley-clean-host-after.json', 'host-after.json')]:
        shutil.copy2(ROOT / 'build' / source, REPORT / name)
    for name in ('timing-plan.json', 'measure-five.py', 'pre-campaign-host.json'):
        shutil.copy2(PREPARATION / name, REPORT / name)


def package(names):
    archive = REPORT / 'artifacts.tar.xz'
    if archive.exists():
        raise ValueError('refusing to replace an evidence archive')
    paths = [path for name in names for path in
             ((REPORT / name).rglob('*') if (REPORT / name).is_dir() else [REPORT / name]) if path.is_file()]
    members = {str(path.relative_to(REPORT)): dict(sha256=digest(path), bytes=path.stat().st_size) for path in paths}
    command = ['tar', '--sort=name', '--mtime=@0', '--owner=0', '--group=0', '--numeric-owner',
               '-I', 'xz -T1 -6', '-cf', str(archive), *names]
    record = earley_port.bounded_execute(command, REPORT, os.environ, timeout=120)
    save('package-command.json', record)
    if record.get('returncode') != 0 or record.get('error'):
        raise ValueError('packaging failed')
    seen = set()
    with tarfile.open(archive, 'r:xz') as packed:
        for member in packed:
            if member.isfile():
                if hashlib.sha256(packed.extractfile(member).read()).hexdigest() != members[member.name]['sha256']:
                    raise ValueError('archive member differs')
                seen.add(member.name)
    if seen != set(members):
        raise ValueError('archive member set differs')
    save('manifest.json', dict(archive=archive.name, sha256=digest(archive), bytes=archive.stat().st_size,
         preparation_archive=dict(path='../2026-10-14-strict-earley-preparation/artifacts.tar.xz',
                                  sha256=digest(PREPARATION / 'artifacts.tar.xz')), members=members))
    save('archive-verification.json', dict(complete=True, files=len(seen), sha256=digest(archive)))


def main():
    plan = json.loads((PREPARATION / 'timing-plan.json').read_text())
    campaign = json.loads((RUN / 'campaign.json').read_text())
    runner.verify(plan)
    check_samples(plan, campaign)
    save('summary.json', summarize(plan, campaign))
    save('verification.json', dict(complete=True, frozen_identities=len(plan['identities']),
         samples=30, exact_raw_records=True, valid_output_framing=True, balanced_retained_positions=True,
         aggregate_arithmetic_matches=True, no_benchmark_rerun=True,
         cleanup='Owned groups killed; direct child reaped; no live group members; adopted zombies may remain.'))
    copy_records()
    package(['measurements', 'summary.json', 'verification.json', 'quiet-window.json',
             'host-before.json', 'host-after.json', 'pre-campaign-host.json',
             'timing-plan.json', 'measure-five.py', 'README.md', 'package.py'])
    print('Verified 30 samples, 161 identities and comparison archive; no benchmark rerun')


if __name__ == '__main__':
    main()
