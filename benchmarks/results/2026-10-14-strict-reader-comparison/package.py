#!/usr/bin/env python3
"""Validate every completed sample and archive the selected frozen artifacts."""

import hashlib
import importlib.util
import json
import math
from pathlib import Path
import shutil
import tarfile

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
FREEZE = REPORT.parent / '2026-10-14-strict-reader-timing-correction'
PREPARATION = REPORT.parent / '2026-10-14-strict-reader-preparation'
CAMPAIGN = ROOT / 'build/strict-reader-seven-campaign-attempt2-20261014'


# ---- Validate exact commands, outputs, order and process cleanup ----

def load(path):
    return json.loads(path.read_text())


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_runner():
    spec = importlib.util.spec_from_file_location('reader_timing', FREEZE / 'measure-seven.py')
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    return runner


def checked_samples(plan, campaign, runner):
    if not campaign['complete'] or len(campaign['samples']) != 112 or campaign['plan'] != plan:
        raise ValueError('campaign is incomplete or differs from the reviewed plan')
    for index, (scheduled, sample) in enumerate(zip(plan['schedule'], campaign['samples'], strict=True)):
        if sample != load(CAMPAIGN / f'sample-{index:02}.json') or any(sample[key] != value for key, value in scheduled.items()):
            raise ValueError('raw sample or predetermined schedule differs')
        config = plan['systems'][scheduled['benchmark']][scheduled['system']]
        if sample['command'] != [plan['taskset'], '-c', str(plan['cpu']), *config['argv']] or sample['cwd'] != config['cwd']:
            raise ValueError('sample command differs from the frozen plan')
        if sample['environment'] != plan['environment'] or sample['inherited_environment'] != plan['inherited_environment']:
            raise ValueError('sample environment differs from the frozen plan')
        if sample['status'] != 'valid' or sample['cleanup']['live_members'] or sample['executing_descendants']:
            raise ValueError('sample did not finish validly with a stopped owned group')
        if sample['pid'] != sample['process_group'] or sample['cleanup']['process_group'] != sample['process_group']:
            raise ValueError('cleanup refers to a different process group')
        if runner.workload_seconds(plan, scheduled, sample) != sample['workload_seconds']:
            raise ValueError('duration differs from validated complete output')
    return campaign['samples']


# ---- Recompute medians without trusting the runner summary ----

def statistics(rows, field):
    values = sorted(row[field] for row in rows)
    if len(values) != 7 or any(not math.isfinite(value) or value < 0 for value in values):
        raise ValueError('expected seven finite retained durations')
    return values[3], [values[0], values[-1]]


def summarize(plan, samples):
    workloads, ratios = {}, {}
    for benchmark, systems in plan['systems'].items():
        workloads[benchmark] = {}
        for system in systems:
            rows = [row for row in samples if row['benchmark'] == benchmark and row['system'] == system and row['retained']]
            work, work_range = statistics(rows, 'workload_seconds')
            process, process_range = statistics(rows, 'process_seconds')
            workloads[benchmark][system] = dict(samples=7, workload_median=work, workload_range=work_range,
                                                process_median=process, process_range=process_range)
        medians = {system: row['workload_median'] for system, row in workloads[benchmark].items()}
        ratios[benchmark] = dict(production_v8_over_system={system: medians['strict-v8'] / value for system, value in medians.items()},
            system_over_original_chez={system: value / medians['chez-original'] for system, value in medians.items()},
            native_over_common_module_v8=medians['strict-native'] / medians['strict-v8-native-module'],
            native_over_rust_native=medians['strict-native'] / medians['rust-native'])
    return dict(complete=True, total_samples=112, retained_samples=98, discarded_samples=14,
                workloads=workloads, ratios=ratios)


# ---- Preserve immediate host policy and every raw record ----

def copy_campaign(summary):
    shutil.copytree(CAMPAIGN, REPORT / 'measurements')
    for suffix in ('stdout', 'stderr'):
        shutil.copyfile(ROOT / ('build/strict-reader-seven-campaign-attempt2.' + suffix), REPORT / ('campaign.' + suffix))
    before, after = load(CAMPAIGN / 'host-before.json'), load(CAMPAIGN / 'host-after.json')
    fixed = lambda value: {key: item for key, item in value['policy'].items() if not key.endswith('/scaling_cur_freq')}
    if fixed(before) != fixed(after) or before['affinity'] != after['affinity']:
        raise ValueError('immediate policy or affinity changed; disclose before publication')
    if (REPORT / 'campaign.stderr').read_bytes():
        raise ValueError('campaign runner wrote stderr')
    if len((REPORT / 'campaign.stdout').read_text().splitlines()) != 112:
        raise ValueError('campaign progress transcript is incomplete')
    save(REPORT / 'summary.json', summary)
    save(REPORT / 'verification.json', dict(valid_samples=112, retained_samples=98,
        schedule_commands_environment_outputs_match=True, all_groups_stopped=True,
        independently_recomputed_summary_matches=True, fixed_cpu_policy_before_after_equal=True,
        instantaneous_frequency_may_vary=True, final_frozen_identities_verified=True))


# ---- Archive selected replay inputs, not unrelated build directories ----

def archive_inputs(plan):
    files, external = {}, {}
    for name, expected in plan['identities'].items():
        path = Path(name)
        if path.is_relative_to(ROOT):
            files['frozen/' + str(path.relative_to(ROOT))] = path
        else:
            external[name] = expected
    extras = [FREEZE / 'timing-plan.json', PREPARATION / 'timing-plan.json', PREPARATION / 'measure-seven.py']
    extras += [path for path in FREEZE.rglob('*') if path.is_file() and '__pycache__' not in path.parts]
    for path in extras:
        files['frozen/' + str(path.relative_to(ROOT))] = path
    for path in sorted(REPORT.rglob('*')):
        if path.is_file() and '__pycache__' not in path.parts:
            files['comparison/' + str(path.relative_to(REPORT))] = path
    return dict(sorted(files.items())), external


def write_archive(files, external):
    archive = REPORT / 'artifacts.tar.xz'
    if archive.exists():
        raise ValueError('do not replace an existing comparison archive')
    hashes = {name: digest(path) for name, path in files.items()}
    with tarfile.open(archive, 'w:xz', preset=6) as target:
        for name, path in files.items():
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = path.stat().st_size, path.stat().st_mode & 0o777, 0
            with path.open('rb') as contents:
                target.addfile(info, contents)
    save(REPORT / 'manifest.json', dict(archive_sha256=digest(archive), files=hashes, external_tools=external))
    verified = {}
    with tarfile.open(archive, 'r:xz') as source:
        for member in source:
            if not member.isfile() or member.name in verified:
                raise ValueError('archive contains a nonregular or duplicate member')
            verified[member.name] = hashlib.sha256(source.extractfile(member).read()).hexdigest()
    if verified != hashes:
        raise ValueError('archive differs from its complete member manifest')
    save(REPORT / 'archive-verification.json', dict(members=len(verified), all_hashes_match=True,
        archive_sha256=digest(archive), bytes=archive.stat().st_size))


def main():
    runner, plan = load_runner(), load(FREEZE / 'timing-plan.json')
    runner.verify(plan)
    campaign = load(CAMPAIGN / 'campaign.json')
    summary = summarize(plan, checked_samples(plan, campaign, runner))
    if summary['workloads'] != campaign['summary']:
        raise ValueError('recomputed medians or ranges differ from the runner')
    copy_campaign(summary)
    files, external = archive_inputs(plan)
    write_archive(files, external)
    print('Verified112 samples,111 frozen identities and all', len(files), 'archive members')


if __name__ == '__main__':
    main()
