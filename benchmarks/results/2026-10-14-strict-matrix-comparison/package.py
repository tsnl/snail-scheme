#!/usr/bin/env python3
"""Recompute all reviewed sample results and archive the completed campaign."""

import hashlib
import importlib.util
import json
import math
from pathlib import Path
import shutil
import tarfile

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
PREPARATION_REPORT = REPORT.parent / '2026-10-14-strict-matrix-preparation'
CAMPAIGN = ROOT / 'build/matrix-seven-system-campaign-20261014'


# ---- Recheck schedule, output, process ownership and frozen identities ----

def load(path):
    return json.loads(path.read_text())


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_runner():
    module = importlib.util.spec_from_file_location('matrix_timing', PREPARATION_REPORT / 'measure-seven.py')
    runner = importlib.util.module_from_spec(module)
    module.loader.exec_module(runner)
    return runner


def checked_samples(plan, campaign, runner):
    if not campaign['complete'] or len(campaign['samples']) != 56 or campaign['plan'] != plan:
        raise ValueError('campaign is incomplete or differs from the frozen plan')
    for index, (scheduled, sample) in enumerate(zip(plan['schedule'], campaign['samples'], strict=True)):
        if sample != load(CAMPAIGN / f'sample-{index:02}.json') or any(sample[key] != value for key, value in scheduled.items()):
            raise ValueError('raw sample or predetermined schedule differs')
        config = plan['systems'][scheduled['system']]
        if sample['command'] != [plan['taskset'], '-c', str(plan['cpu']), *config['argv']] or sample['cwd'] != config['cwd']:
            raise ValueError('sample command differs from the frozen plan')
        if sample['status'] != 'valid' or sample['cleanup']['live_members'] or sample['executing_descendants']:
            raise ValueError('sample did not finish validly with a stopped owned group')
        if runner.workload_seconds(plan, sample['system'], sample) != sample['workload_seconds']:
            raise ValueError('recorded workload duration differs from validated output')
    return campaign['samples']


def statistics(rows, field):
    values = sorted(row[field] for row in rows)
    if len(values) != 7 or any(not math.isfinite(value) or value < 0 for value in values):
        raise ValueError('expected seven finite retained durations')
    return values[3], [values[0], values[-1]]


def summarize(plan, samples):
    systems = {}
    for name in plan['systems']:
        rows = [row for row in samples if row['system'] == name and row['retained']]
        work, work_range = statistics(rows, 'workload_seconds')
        process, process_range = statistics(rows, 'process_seconds')
        systems[name] = dict(samples=7, workload_median=work, workload_range=work_range,
                             process_median=process, process_range=process_range)
    medians = {name: row['workload_median'] for name, row in systems.items()}
    return dict(complete=True, total_samples=56, retained_samples=49, systems=systems,
        production_v8_ratios={name: medians['strict-v8'] / value for name, value in medians.items()},
        native_to_common_v8=medians['strict-native'] / medians['strict-v8-native-final'],
        adapted_to_original_chez=medians['chez-adapted'] / medians['chez-original'],
        rust_wasm_to_production_v8=medians['rust-wasm-v8'] / medians['strict-v8'])


# ---- Keep immediate policy, coordination and raw records beside the summary ----

def copy_campaign(summary):
    shutil.copytree(CAMPAIGN, REPORT / 'measurements')
    for label in ('before', 'after', 'launch'):
        shutil.copy2(ROOT / f'build/matrix-seven-system-campaign-{label}.json', REPORT / f'host-{label}.json')
    shutil.copy2(ROOT / 'build/run-matrix-reviewed-campaign.py', REPORT / 'run-reviewed-campaign.py')
    save(REPORT / 'summary.json', summary)
    before, after = load(REPORT / 'host-before.json'), load(REPORT / 'host-after.json')
    if before['models'] != after['models'] or before['frequency'] != after['frequency']:
        raise ValueError('immediate before/after CPU policy differs; disclose before publishing')
    save(REPORT / 'quiet-window.json', dict(release=load(REPORT / 'host-launch.json'),
        coordination='Parent confirmed every other agent execution/compression/build handle terminal and heavy work held.',
        clean_processes=56, retained_processes=49, replacements=0, all_owned_groups_stopped=True,
        immediate_cpu_policy_before_after_equal=True, packaging_started_after_all_clean_clocks=True))


def archive_inputs(plan):
    files, external = {}, {}
    for name, expected in plan['identities'].items():
        path = Path(name)
        if path.is_relative_to(ROOT):
            files['frozen/' + str(path.relative_to(ROOT))] = path
        else:
            external[name] = expected
    for path in sorted(REPORT.rglob('*')):
        if path.is_file() and '__pycache__' not in path.parts:
            files['comparison/' + str(path.relative_to(REPORT))] = path
    files['frozen/plan.json'] = PREPARATION_REPORT / 'timing-plan.json'
    return files, external


def write_archive(files, external):
    archive = REPORT / 'artifacts.tar.xz'
    if archive.exists():
        raise ValueError('comparison archive already exists; do not replace evidence')
    with tarfile.open(archive, 'w:xz', preset=6) as target:
        for name, path in files.items():
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = path.stat().st_size, path.stat().st_mode & 0o777, 0
            with path.open('rb') as contents:
                target.addfile(info, contents)
    save(REPORT / 'manifest.json', dict(archive_sha256=digest(archive),
         files={name: digest(path) for name, path in files.items()}, external_tools=external))


def main():
    runner, plan = load_runner(), load(PREPARATION_REPORT / 'timing-plan.json')
    runner.verify(plan)
    campaign = load(CAMPAIGN / 'campaign.json')
    summary = summarize(plan, checked_samples(plan, campaign, runner))
    if summary['systems'] != campaign['summary']:
        raise ValueError('independently recomputed medians/ranges differ')
    copy_campaign(summary)
    files, external = archive_inputs(plan)
    write_archive(files, external)
    print('Verified 56 raw records, seven retained medians per system and', len(plan['identities']), 'frozen identities; archived', len(files), 'files')


if __name__ == '__main__':
    main()
