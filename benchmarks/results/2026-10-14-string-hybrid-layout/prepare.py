"""Freeze one String-only compiler change and executable operation controls."""

from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = Path(__file__).resolve().parent
PREVIOUS = Path('/tmp/snail-gc-string-block-preparation-20261014')
FREEZE = Path('/tmp/snail-string-hybrid-preparation-20261014')
SCALARS = [0, 233, 128512, 1114111, 769]
GROWTH = [(16, 200000), (64, 100000), (1024, 10000),
          (4096, 2500), (8192, 1250), (32768, 500), (500000, 100)]
LENGTHS = [22, 2038, 8192, 8193, 65526]


# ---- Exact source, artifact and tool identities ----


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def compiler_files(root):
    return [*root.glob('src/**/*.sld'), root / 'scripts/build-strict',
            root / 'tests/build-strict-program.scm']


def source_differences(first, second):
    return [str(path.relative_to(first)) for path in compiler_files(first)
            if path.read_bytes() != (second / path.relative_to(first)).read_bytes()]


def freeze_compilers():
    for variant, previous in [('flat', 'baseline'), ('blocks', 'candidate'), ('hybrid', 'baseline')]:
        shutil.copytree(PREVIOUS / previous, FREEZE / variant)
    compiler = FREEZE / 'hybrid/compiler-source'
    for path in compiler_files(ROOT):
        relative = path.relative_to(ROOT)
        assert path.read_bytes() == subprocess.check_output(['git', 'show', REVISION + ':' + str(relative)], cwd=ROOT)
        shutil.copy2(path, compiler / relative)
    assert source_differences(FREEZE / 'flat/compiler-source', compiler) == ['src/snail-scheme/strict-wasm.sld']
    assert source_differences(FREEZE / 'blocks/compiler-source', compiler) == ['src/snail-scheme/strict-wasm.sld']


def command_record(command, directory, accepted=True):
    result = preparation.execute(command, directory, ENVIRONMENT)
    if accepted:
        preparation.require_success(result)
        assert not result['stderr'], result
    else:
        assert result['returncode'] != 0 and 'AssertionError' in result['stderr'], result
    return dict(result, accepted=accepted)


# ---- Unchanged full canonical source and complete-value probes ----


def prepare_canonical():
    directory = FREEZE / 'hybrid/string'
    for name in ('strict-output-probe', 'strict-alias-probe', 'chez-output-original',
                 'chez-output-adapted', 'chez-alias-original', 'chez-alias-adapted'):
        shutil.rmtree(directory / name)
    preparation.ROOT = FREEZE / 'hybrid/compiler-source'
    preparation.build_strict(directory, TOOLS, ENVIRONMENT)
    preparation.validate_strict(directory, TOOLS, ENVIRONMENT)
    preparation.validate_string_outputs(directory, runner, TOOLS, ENVIRONMENT)
    for name in ('strict.scm', 'adapted-kernel.scm', 'original-kernel.scm', 'spec.json', 'input.txt'):
        assert (directory / name).read_bytes() == (FREEZE / 'flat/string' / name).read_bytes(), name
    print('Canonical raw/optimized counts 1/2/100, full payload/store, Unicode, alias and harness probes passed.', flush=True)


# ---- Scalar loads and stores use the same source in all three compilers ----


def scalar_specification(operation, length, count):
    cycles, rest = divmod(length, len(SCALARS))
    checksum = cycles * sum(SCALARS) + sum(SCALARS[:rest])
    expected = checksum * count if operation == 'ref' else length * count
    return dict(name='scalar-' + operation, operation=operation, count=count,
                inputs=[length], expected=str(expected), barriers_per_iteration=1,
                setup_barriers=0, scalar_operations=length * count)


def build_scalars():
    for variant in ('flat', 'blocks', 'hybrid'):
        preparation.ROOT = FREEZE / variant / 'compiler-source'
        for operation in ('ref', 'set'):
            directory = FREEZE / variant / ('scalar-' + operation)
            directory.mkdir()
            shutil.copy2(EVIDENCE / ('scalar-' + operation + '.scm'), directory / 'strict.scm')
            shutil.copy2(EVIDENCE / 'scalar-host.mjs', directory / 'host.mjs')
            save(directory / 'spec.json', dict(scalar_specification(operation, 22, 1),
                                             additional_exports=['probe-character', 'probe-length']))
            preparation.build_strict(directory, TOOLS, ENVIRONMENT)


def validate_scalar(variant, operation):
    directory = FREEZE / variant / ('scalar-' + operation)
    checks = []
    for length in (0, 1, 22, 8192, 8193, 65526):
        for count in (0, 1, 5):
            path = directory / f'validation-{length}-{count}.spec.json'
            save(path, scalar_specification(operation, length, count))
            for suffix in ('.raw.wasm', ''):
                command = [TOOLS['NODE'], directory / 'host.mjs', directory / ('strict.wasm' + suffix), path, '--validate']
                checks.append(command_record(command, directory))
                save(directory / 'validation.json', checks)
    path = directory / 'wrong-result.spec.json'
    save(path, dict(scalar_specification(operation, 22, 5), expected='-1'))
    checks.append(command_record([TOOLS['NODE'], directory / 'host.mjs', directory / 'strict.wasm', path, '--validate'], directory, False))
    save(directory / 'validation.json', checks)


def prepare_scalars():
    build_scalars()
    for variant in ('flat', 'blocks', 'hybrid'):
        for operation in ('ref', 'set'):
            validate_scalar(variant, operation)
    print('Six scalar artifacts passed raw/optimized payload, intermediate-store, zero-count/length and wrong-result controls.', flush=True)


# ---- Runtime size controls retain the complete growth/copy program ----


def final_length(threshold):
    length = 6
    while length <= threshold:
        length = 2 * length + 10
    return length


def prepare_growth():
    controls = []
    for threshold, count in GROWTH:
        directory = FREEZE / 'controls' / ('growth-' + str(threshold))
        directory.mkdir(parents=True)
        spec = json.loads((FREEZE / 'flat/string/spec.json').read_text())
        spec.update(count=count, inputs=[threshold, 2, final_length(threshold)], original_expected=final_length(threshold))
        save(directory / 'spec.json', spec)
        save(directory / 'count-one.json', dict(spec, count=1))
        controls.append(dict(name=directory.name, case='string', host='host.mjs', spec=directory / 'spec.json', expected='1'))
    return controls


def prepare_operation_specs():
    controls = []
    for operation in ('ref', 'set'):
        for length in LENGTHS:
            directory = FREEZE / 'controls' / f'{operation}-{length}'
            directory.mkdir(parents=True)
            spec = scalar_specification(operation, length, max(1, 20000000 // length))
            save(directory / 'spec.json', spec)
            controls.append(dict(name=directory.name, case='scalar-' + operation,
                                 host='scalar-' + operation + '/host.mjs', spec=directory / 'spec.json', expected=spec['expected']))
    return controls


def validate_growth(controls):
    for control in controls:
        directory = control['spec'].parent
        checks = []
        for variant in ('flat', 'blocks', 'hybrid'):
            command = [TOOLS['NODE'], FREEZE / variant / 'host.mjs', FREEZE / variant / 'string/strict.wasm', directory / 'count-one.json', '--validate']
            checks.append(command_record(command, directory))
        save(directory / 'validation.json', checks)


# ---- Parent-owned balanced timing plans, prepared without execution ----


def variants(control):
    return [dict(name=variant, kind='json', expected=control['expected'],
                 command=[TOOLS['NODE'], str(FREEZE / variant / control['host']),
                          str(FREEZE / variant / control['case'] / 'strict.wasm'), str(control['spec'])],
                 cwd=str(control['spec'].parent), environment={}, stdin=None)
            for variant in ('flat', 'blocks', 'hybrid')]


def freeze_plans(controls):
    (FREEZE / 'plans').mkdir()
    files = sorted([str(path) for path in FREEZE.rglob('*') if path.is_file()]
                   + list(TOOLS.values()))
    identities = [dict(path=path, sha256=digest(path)) for path in files]
    for control in controls:
        plan = dict(name=control['name'], cpu=5, taskset=TOOLS['TASKSET'], rounds=6,
                    variants=variants(control), files=files, identities=identities,
                    protocol='Parent-coordinated timing only. One discarded rotation and six retained cyclic rotations; '
                             'every variant occupies each position twice. Same source/input within each row. '
                             'Scalar final-payload verification occurs after the workload timer.')
        save(FREEZE / 'plans' / (control['name'] + '.json'), plan)


def finish(controls):
    artifacts = {variant: {case: {name: digest(FREEZE / variant / case / name)
                 for name in ('strict.scm', 'strict.wasm.raw.wasm', 'strict.wasm', 'strict.optimized.wat')}
                 for case in ('string', 'scalar-ref', 'scalar-set')} for variant in ('flat', 'blocks', 'hybrid')}
    report = dict(date=datetime.now(timezone.utc).isoformat(), compiler_commit=REVISION,
                  compiler_differences=['src/snail-scheme/strict-wasm.sld'], artifacts=artifacts,
                  controls=[dict(name=control['name'], plan=str(FREEZE / 'plans' / (control['name'] + '.json')),
                                 spec=json.loads(control['spec'].read_text())) for control in controls],
                  measurement='No comparative timings executed; parent coordinates the clean CPU window.')
    save(FREEZE / 'handoff.json', report)
    save(FREEZE / 'manifest.json', dict(compiler_commit=REVISION, files={
        str(path.relative_to(FREEZE)): digest(path) for path in FREEZE.rglob('*') if path.is_file()}))
    print(json.dumps(dict(handoff=str(FREEZE / 'handoff.json'), compiler_commit=REVISION,
                          hybrid_canonical_sha256=artifacts['hybrid']['string']['strict.wasm'])), flush=True)


# ---- Preparation entry point ----

REVISION = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
sys.path.insert(0, str(ROOT / 'benchmarks/strict-suite'))
spec = importlib.util.spec_from_file_location('preparation', ROOT / 'benchmarks/strict-suite/measure.py')
preparation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preparation)
runner = preparation.upstream_runner()
TOOLS = preparation.tool_paths(('string',))
ENVIRONMENT = {**os.environ, **TOOLS, 'BINARYEN_CORES': '1'}
ENVIRONMENT.pop('NODE_OPTIONS', None)
FREEZE.mkdir(exist_ok=False)
shutil.copy2(__file__, FREEZE / 'prepare.py')
shutil.copy2(ROOT / 'benchmarks/results/2026-10-14-string-size-controls/measure.py', FREEZE / 'measure.py')
freeze_compilers()
prepare_canonical()
prepare_scalars()
controls = prepare_growth() + prepare_operation_specs()
validate_growth([control for control in controls if control['case'] == 'string'])
freeze_plans(controls)
finish(controls)
