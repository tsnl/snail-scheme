#!/usr/bin/env python3
"""Independently audit prepared controls and freeze a balanced serial schedule."""

import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tarfile

REPORT = Path(__file__).resolve().parent
ROOT = REPORT.parents[2]
ORIGINAL = ROOT / 'benchmarks/results/2026-10-14-strict-integer-controls'
CONTROLS = Path('/tmp/snail-strict-big-integer-20261014/build/strict-integer-controls')
CORPUS = CONTROLS.parents[1] / 'benchmarks/r7rs-benchmarks'


# ---- Original evidence must identify every archived byte and command artifact ----

def load(path):
    return json.loads(path.read_text())


def runner():
    spec = importlib.util.spec_from_file_location('integer_measurement', REPORT / 'measure.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def audit_archives(measure):
    archives = {}
    for name, expected in load(ORIGINAL / 'manifest.json')['archives'].items():
        path = ORIGINAL / name
        if measure.digest(path) != expected['sha256'] or path.stat().st_size != expected['bytes']:
            raise ValueError('original archive changed: ' + name)
        entries = {}
        with tarfile.open(path) as archive:
            for member in archive:
                relative = Path(member.name)
                if relative.is_absolute() or '..' in relative.parts or not (member.isdir() or member.isfile()):
                    raise ValueError('unexpected archive entry: ' + member.name)
                if member.isfile():
                    contents = archive.extractfile(member).read()
                    if contents != (CONTROLS / relative).read_bytes():
                        raise ValueError('archive differs from actual frozen artifact: ' + member.name)
                    entries[member.name] = measure.digest(CONTROLS / relative)
        archives[name] = dict(**expected, files=entries)
    return archives


def audit_records(measure, supervisor):
    audit = load(CONTROLS / 'evidence-audit.json')
    rows = []
    for name in audit['validated_guest_records']:
        path, record = CONTROLS / name, load(CONTROLS / name)
        failed_control = ('chez-' in name or 'rust-reference/' in name) and any(
            label in name for label in ('count-0.json', 'wrong-result.json', 'wrong-final.json'))
        if (record['timeout'] or record['executing_descendants']
                or supervisor.group_members(record['process_group'])
                or (record['returncode'] == 0) == failed_control):
            raise ValueError('original validation/process ownership differs: ' + name)
        workload = 'chudnovsky' if 'chudnovsky' in name else 'pi'
        if failed_control:
            message = 'complete result differs' if 'chez-' in name else 'assertion'
            if message not in record['stderr']:
                raise ValueError('negative control did not reach full predicate: ' + name)
        else:
            expected = load(CONTROLS / workload / 'full.spec.json')['output']
            if 'retained-results/' in name:
                count = int(path.stem.rsplit('-', 1)[1])
                expected *= count
            elif 'count-0.json' in name:
                expected = '()\n'
            if name.startswith('rust-reference/'):
                expected = 'Result: ' + expected
            if record['stdout'] != expected or record['stderr']:
                raise ValueError('complete original result differs: ' + name)
        if '+!CSVLINE!+' in record['stdout']:
            raise ValueError('preparation unexpectedly started a workload clock: ' + name)
        rows.append(dict(path=name, sha256=measure.digest(path), expected_rejection=failed_control,
                         process_group=record['process_group'], executing_members=[]))
    if len(rows) != 152 or len({row['path'] for row in rows}) != 152:
        raise ValueError('complete original validation set differs')
    return rows


# ---- Regenerate every strict/compiled-Chez source and restore each source ledger ----

def audit_sources(measure):
    directory = CONTROLS / 'frozen/benchmarks/strict-suite'
    sys.path.insert(0, str(directory))
    import integer_controls
    import integer_ports
    import data_ports
    for module in (integer_controls, integer_ports, data_ports):
        if Path(module.__file__).resolve().parent != directory.resolve():
            raise ValueError('preparation import loaded outside the frozen directory')
    integer_ports.CORPUS = CORPUS
    identities = load(ORIGINAL / 'manifest.json')['source_sha256']
    for relative, expected in identities.items():
        if measure.digest(ROOT / relative) != expected or measure.digest(CONTROLS / 'frozen' / relative) != expected:
            raise ValueError('frozen preparation source differs: ' + relative)
    result = {}
    for name in measure.WORKLOADS:
        directory = CONTROLS / name
        original, adapted = (directory / 'original.scm').read_text(), (directory / 'adapted.scm').read_text()
        if original != (CORPUS / 'src' / (name + '.scm')).read_text():
            raise ValueError('original corpus source differs: ' + name)
        if (directory / 'input').read_bytes() != (CORPUS / 'inputs' / (name + '.input')).read_bytes():
            raise ValueError('original full input differs: ' + name)
        if integer_ports.restore(adapted, load(directory / 'edits.json')) != original:
            raise ValueError('adaptation ledger is not reversible: ' + name)
        regenerated, edits = integer_ports.adaptation(name, original)
        if regenerated != adapted or edits != load(directory / 'edits.json'):
            raise ValueError('adaptation generation changed: ' + name)
        if integer_ports.strict_source(name, adapted) != (directory / 'strict.scm').read_text():
            raise ValueError('strict source generation changed: ' + name)
        for mode in ('original', 'adapted', 'limbs'):
            source = integer_controls.chez_program(name, original, adapted, mode)
            if source != (directory / ('chez-' + mode + '.sps')).read_text():
                raise ValueError('compiled Chez source generation changed: ' + name + '/' + mode)
        rust = CONTROLS / 'rust-reference'
        source = (rust / 'src/bin' / (name + '.rs')).read_text()
        restored = integer_ports.restore(source, load(rust / (name + '-reporting-edits.json')))
        if restored != (ROOT / 'benchmarks/wasm-reference/src/bin' / (name + '.rs')).read_text():
            raise ValueError('Rust reporting ledger does not restore the reference: ' + name)
        spec = load(directory / 'full.spec.json')
        if spec != integer_ports.specification(name, (directory / 'input').read_text()):
            raise ValueError('complete input specification differs: ' + name)
        result[name] = dict(count=spec['count'], inputs=spec['inputs'], numerical_components=len(spec['expected']),
                            output_sha256=measure.digest(ORIGINAL / name / 'complete.output'))
    return result


# ---- Reuse the corrected, unchanged supervisor and freeze its entire local closure ----

def freeze_supervisor(measure):
    source = ROOT / 'benchmarks/results/2026-10-14-strict-reader-timing-correction/supervisor'
    destination = REPORT / 'supervisor'
    destination.mkdir(exist_ok=True)
    for path in sorted(source.glob('*.py')):
        shutil.copy2(path, destination / path.name)
    return {path.name: dict(sha256=measure.digest(path), local_imports=measure.local_imports(path))
            for path in sorted(destination.glob('*.py'))}


def artifact_identities(measure, original):
    files = {Path(__file__), REPORT / 'measure.py', REPORT / 'verify.py', CONTROLS / 'timing-plan.json', CONTROLS / 'tools.json'}
    files.update((REPORT / 'supervisor').glob('*.py'))
    files.update(path for path in (CONTROLS / 'frozen').rglob('*') if path.is_file())
    for row in original['commands']:
        for value in [*row['command'], row.get('stdin', '')]:
            if value and Path(value).is_file():
                if measure.digest(value) != row['artifact_sha256'][value]:
                    raise ValueError('original planned artifact changed: ' + value)
                files.add(Path(value))
    files.add(Path(shutil.which('taskset')))
    files.add(Path(sys.executable))
    rust = CONTROLS / 'rust-reference'
    files.update(rust / name for name in ('Cargo.toml', 'Cargo.lock', 'src/lib.rs'))
    for name in measure.WORKLOADS:
        directory = CONTROLS / name
        files.update(directory / item for item in ('original.scm', 'adapted.scm', 'strict.scm', 'input', 'full.spec.json',
                     'full.native-input', 'edits.json', 'native', 'production.wasm', 'native-final.wasm'))
        files.add(ORIGINAL / name / 'retention.json')
        files.update(directory / ('chez-' + mode + suffix)
                     for mode in ('original', 'adapted', 'limbs') for suffix in ('.sps', '.so', '-compile.sps', '-compile.json'))
        native, = directory.glob('native.native-*')
        files.update(native / item for item in ('build.json', 'module.ll', 'optimized.wasm', 'provider-0.o'))
        if measure.digest(native / 'optimized.wasm') != measure.digest(directory / 'native-final.wasm'):
            raise ValueError('native-final module is not the native compiler input: ' + name)
        build = load(native / 'build.json')['sha256']
        for item in ('native', 'production.wasm'):
            if measure.digest(directory / item) != build[str(directory / item)]:
                raise ValueError('native build identity differs: ' + name + '/' + item)
        for relative in ('benchmarks/strict-suite/integer-control-entry.c', 'benchmarks/strict-suite/integer-provider.c',
                         'benchmarks/strict-suite/integer-provider.h'):
            frozen = CONTROLS / 'frozen' / relative
            if measure.digest(frozen) != build[str(CONTROLS.parents[1] / relative)]:
                raise ValueError('native provider/entry build identity differs: ' + relative)
        files.update(rust / item for item in (name + '.raw.wasm', name + '.wasm', name + '-native',
                     'src/bin/' + name + '.rs', name + '-reporting-edits.json'))
    return {str(path): measure.digest(path) for path in sorted(files)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timeout', type=int, default=1800, help='predeclared process deadline, seconds')
    parser.add_argument('--audit-sources', action='store_true', help='isolated preparation imports and source regeneration')
    options = parser.parse_args()
    measure = runner()
    if options.audit_sources:
        print(json.dumps(audit_sources(measure)))
        return
    imports = freeze_supervisor(measure)
    supervisor = measure.load_supervisor({'supervisor': str(REPORT / 'supervisor')})
    original = load(CONTROLS / 'timing-plan.json')
    if original != load(ORIGINAL / 'timing-plan.json'):
        raise ValueError('actual original timing plan differs from the landed report')
    for name, expected in original['environment_guard'].items():
        if os.environ.get(name) != expected:
            raise ValueError('original environment guard differs: ' + name)
    for name in ('NODE', 'CHEZ', 'PYTHON'):
        tool = load(CONTROLS / 'tools.json')[name]
        if measure.digest(tool['path']) != tool['sha256'] or str(Path(tool['path']).resolve()) != tool['realpath']:
            raise ValueError('original runtime identity changed: ' + name)
    source_record = supervisor.execute([sys.executable, '-I', '-B', __file__, '--audit-sources'],
                                        REPORT, os.environ, timeout=120)
    measure.save(REPORT / 'source-regeneration.json', source_record)
    if source_record.get('returncode') != 0 or source_record['timeout'] or source_record['executing_descendants']:
        raise ValueError('isolated source regeneration failed')
    sources = json.loads(source_record['stdout'])
    archives, records = audit_archives(measure), audit_records(measure, supervisor)
    plan = dict(cpu=5, timeout_seconds=options.timeout, taskset=shutil.which('taskset'),
                supervisor=str(REPORT / 'supervisor'), environment={'BINARYEN_CORES': '1'},
                inherited_environment={name: os.environ.get(name) for name in measure.RECORDED_ENVIRONMENT},
                workloads={name: load(CONTROLS / name / 'full.spec.json') for name in measure.WORKLOADS},
                systems={name: {row['system']: row for row in original['commands'] if row['name'] == name}
                         for name in measure.WORKLOADS}, schedule=measure.schedule(),
                identities=artifact_identities(measure, original),
                clock_boundary=original['clock_boundary'], original_plan=str(CONTROLS / 'timing-plan.json'),
                exclusions='Only the predetermined round -1: one fresh process per system/workload. No replacement or later exclusion.',
                runtime_policy='Default V8 tiers and default GC. Three opacity imports per Scheme iteration stay timed. CPU 5, serial fresh processes.',
                process_clock='Popen through capture, leader reap and bounded group cleanup.',
                comparison='Original/adapted native-bigint Chez, checked limb-body Chez and independent Rust retain arithmetic/layout/ownership differences.')
    measure.verify(plan)
    measure.save(REPORT / 'timing-plan.json', plan)
    measure.save(REPORT / 'independent-audit.json', dict(passed=True, diagnostic_only=True,
                 archives=archives, original_guest_records=records, source_regeneration=sources,
                 supervisor_modules=imports, planned_processes=144, benchmark_processes_started=0))
    print('Audited all archived bytes, 152 original records and source ledgers; froze 144 processes')


if __name__ == '__main__':
    main()
