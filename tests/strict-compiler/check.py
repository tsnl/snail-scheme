#!/usr/bin/env python3
"""Check compiler-port foundations and isolated full-source ordering controls."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/strict-suite'))
import compiler_port
import reader_ports

# Reuse the reviewed process-group owner: timeouts kill and drain descendants,
# and every invocation retains its return code and unmodified output streams.
execute = runpy.run_path(str(ROOT / 'scripts/test-strict-integer'))['execute']
ENVIRONMENT = dict(os.environ, BINARYEN_CORES='1')


# ---- Identical bodies, with target-specific assertion entry points ----


def chez_source(support, fixture, failure):
    prelude = reader_ports.chez_reader(ROOT, ['datum-boolean', 'datum-boolean-value', 'datum-fail'])
    if failure:
        return prelude + support + fixture
    start, end = list(compiler_port.source_forms(fixture))[-1]
    check = ('(let ((result ' + fixture[start:end] + '))\n'
             '  (unless (= result 42) (error \'probe "unexpected result" result))\n'
             '  (display "PASS compiler internal probe: 42\\n"))\n')
    return prelude + support + fixture[:start] + check


def check_probe(output, name, support_name, failure=None):
    support = (ROOT / f'benchmarks/strict-suite/compiler-{support_name}.scm').read_text() + '\n'
    fixture = (ROOT / f'tests/strict-compiler/{name}.scm').read_text()
    source, chez, wasm = [output / (name + suffix) for suffix in ['.scm', '.chez.scm', '.wasm']]
    source.write_text('(import (snail strict) (snail datum))\n' + support + fixture)
    chez.write_text(chez_source(support, fixture, failure))
    records = [execute(['scheme', '--script', chez], output / f'{name}-chez.json', ENVIRONMENT,
                       expected='error' if failure else 0)]
    execute([ROOT / 'scripts/build-strict', source, wasm], output / f'{name}-build.json', ENVIRONMENT)
    for kind, module in [('raw', Path(str(wasm) + '.raw.wasm')), ('optimized', wasm)]:
        linked = output / f'{name}-linked-{kind}.wasm'
        flags = ['--diagnostic-prune-only'] if kind == 'raw' else []
        execute([ROOT / 'scripts/link-strict-runtime', '--runtime', output / 'runtime.wasm',
                 *flags, module, linked], output / f'{name}-{kind}-link.json', ENVIRONMENT)
        records.append(execute(['node', '--disable-warning=ExperimentalWarning',
                                ROOT / 'tests/strict-compiler/data-probe.mjs', linked],
                               output / f'{name}-{kind}-run.json', ENVIRONMENT,
                               expected='error' if failure else 0))
    native = output / f'{name}-native'
    execute([ROOT / 'scripts/build-native', '--wasm', wasm, native],
            output / f'{name}-native-build.json', ENVIRONMENT)
    records.append(execute([native], output / f'{name}-native-run.json', ENVIRONMENT,
                           expected='error' if failure else 42))
    if failure:
        assert all(failure in record['stderr'] for record in records), records
    print('PASS', name, 'Chez/raw/optimized/native64', flush=True)


# ---- Original source controls and complete input preservation ----


def record_source(output):
    corpus = ROOT / 'benchmarks/r7rs-benchmarks'
    source = (corpus / 'src/compiler.scm').read_text()
    data = (corpus / 'inputs/compiler.input').read_bytes()
    (output / 'compiler-original.scm').write_text(source)
    (output / 'compiler.input').write_bytes(data)
    forms, spec = compiler_port.source_inventory(source), compiler_port.specification(data)
    assert len(forms) == 1345 and sum(form['name'] is not None for form in forms) == 1344
    assert spec['count'] == 2000 and len(spec['expected_lines']) == 497
    suffix = '\n(define after-harness (list #\\( #\\) "quoted ( )"))\n'
    assert compiler_port.kernel(source + suffix).endswith(suffix)
    inventory = dict(source_sha256=hashlib.sha256(source.encode()).hexdigest(), forms=forms, specification=spec)
    (output / 'source-inventory.json').write_text(json.dumps(inventory, indent=2) + '\n')
    return source


def check_original_controls(output, source):
    prefixes = ['(define (fatal-err ', '(define (with-exception-handling ',
                '(define (throw-to-exception-handler ', '(define (compiler-abort)']
    controls = '\n'.join(compiler_port.named_form(source, prefix) for prefix in prefixes)
    original = output / 'result-original-probe.scm'
    original.write_text(controls + '\n' + (ROOT / 'tests/strict-compiler/result-original-probe.scm').read_text())
    execute(['scheme', '--script', original], output / 'result-original-chez.json', ENVIRONMENT)
    execute(['scheme', '--script', ROOT / 'tests/strict-compiler/original-map-mutation.scm'],
            output / 'original-map-mutation-chez.json', ENVIRONMENT)


def check_original_collections(output, source):
    names = compiler_port.COLLECTION_NAMES + ['fatal-err', 'with-exception-handling',
             'throw-to-exception-handler', 'compiler-abort', 'compiler-internal-error']
    bodies = []
    for name in names:
        suffix = ')' if name in ('set-empty', 'queue-empty', 'compiler-abort') else ' '
        bodies.append(compiler_port.named_form(source, '(define (' + name + suffix))
    fixture = (ROOT / 'tests/strict-compiler/collections-original-probe.scm').read_text()
    start, end = list(compiler_port.source_forms(fixture))[-1]
    program = '\n'.join(bodies) + '\n' + fixture[:start]
    program += ('(let ((answer ' + fixture[start:end] + '))\n'
                '  (unless (= answer 42) (error \'collections "unexpected result" answer))\n'
                '  (display "PASS compiler collections: 42\\n"))\n')
    path = output / 'collections-original.chez.scm'
    path.write_text(program)
    record = reader_ports.record(output, 'collections-original', ['scheme', '--script', path], ENVIRONMENT)
    diagnostic = ('\n*** ERROR -- Compiler internal error detected\n'
                  '*** in procedure queue-get!, queue is empty\n')
    assert record['stdout'] == diagnostic + 'PASS compiler collections: 42\n', record
    assert not record['stderr'], record
    failures = [('short-zip', "(pair-up '(1) '())"),
                ('missing-node', "(transitive-closure (list (make-gnode 1 '(2))))"),
                ('negative-index', "(list-ref '(1) -1)")]
    for name, expression in failures:
        path = output / ('collections-original-' + name + '.chez.scm')
        path.write_text('\n'.join(bodies) + '\n(display "before host failure\\n")\n'
                        '(with-exception-handling (lambda () ' + expression + ' #t))\n'
                        '(display "unexpected return\\n")\n')
        record = execute(['scheme', '--script', path], output / (name + '-original.json'),
                         ENVIRONMENT, expected='error')
        assert record['stdout'] == 'before host failure\n' and record['stderr'], record
    print('PASS original compiler collection controls and exact queue diagnostic', flush=True)


# ---- Source-derived collections share one build across independent probes ----

COLLECTION_EXPORTS = ['compiler-collection-checks', 'collection-short-zip',
                      'collection-missing-node', 'collection-negative-index']


def prepare_collections(output, source):
    adapted, collections = compiler_port.collection_adaptation(source)
    adapted, diagnostics = compiler_port.diagnostic_adaptation(adapted)
    (output / 'compiler-partially-adapted.scm').write_text(adapted)
    (output / 'adaptation-ledger.json').write_text(json.dumps(dict(
        collections=collections, diagnostics=diagnostics, complete_kernel_typed=False), indent=2) + '\n')
    support = ''.join((ROOT / f'benchmarks/strict-suite/compiler-{name}.scm').read_text() + '\n'
                      for name in ['data', 'result', 'collections'])
    support += compiler_port.diagnostic_contracts()
    support += '\n'.join(entry['after'] for entry in diagnostics + collections) + '\n'
    fixture = (ROOT / 'tests/strict-compiler/collections-probe.scm').read_text()
    start, end = list(compiler_port.source_forms(fixture))[-1]
    fixture = (fixture[:start] + '(: compiler-collection-checks (-> I64))\n'
               '(define (compiler-collection-checks) ' + fixture[start:end] + ')\n(unit)\n')
    path = output / 'collections.scm'
    path.write_text('(import (snail strict) (snail datum) (snail io) (snail write))\n' + support + fixture)
    return support + fixture


def check_collection_result(record, name):
    positive = name == COLLECTION_EXPORTS[0]
    expected = ('\n*** ERROR -- Compiler internal error detected\n'
                '*** in procedure queue-get!, queue is empty\nPASS compiler collections: 42\n'
                if positive else 'before host failure\n')
    assert record['stdout'] == expected, record
    assert not record['stderr'] if positive else bool(record['stderr']), record


def check_collections_chez(output, body):
    for name in COLLECTION_EXPORTS:
        action = ('(let ((answer (compiler-collection-checks)))\n'
                  '  (unless (= answer 42) (error \'collections "unexpected result" answer))\n'
                  '  (write-string "PASS compiler collections: 42\\n"))\n'
                  if name == COLLECTION_EXPORTS[0] else '(' + name + ')\n')
        path = output / (name + '.chez.scm')
        path.write_text(reader_ports.chez_output_program(ROOT, body + action))
        record = execute(['scheme', '--script', path], output / (name + '-chez.json'), ENVIRONMENT,
                         expected=0 if name == COLLECTION_EXPORTS[0] else 'error')
        check_collection_result(record, name)


def check_collection_target(output, system, command):
    for name in COLLECTION_EXPORTS:
        record = execute([*command, name], output / (system + '-' + name + '.json'), ENVIRONMENT,
                         expected=0 if name == COLLECTION_EXPORTS[0] else 'error')
        check_collection_result(record, name)
    print('PASS compiler collections and terminal host failures:', system, flush=True)


def check_collections_targets(output):
    wasm = output / 'collections.wasm'
    for kind, module in [('raw', Path(str(wasm) + '.raw.wasm')), ('optimized', wasm)]:
        linked = output / ('collections-linked-' + kind + '.wasm')
        flags = ['--diagnostic-prune-only'] if kind == 'raw' else []
        execute([ROOT / 'scripts/link-strict-runtime', '--runtime', output / 'runtime.wasm',
                 *flags, module, linked], output / (kind + '-link.json'), ENVIRONMENT)
        check_collection_target(output, kind, ['node', '--disable-warning=ExperimentalWarning',
                                              ROOT / 'tests/strict-compiler/collections-probe.mjs', linked])
    native = output / 'collections-native'
    execute([ROOT / 'scripts/build-native', '--wasm', '--entry-c', ROOT / 'tests/strict-compiler/collections-entry.c',
             wasm, native], output / 'native-build.json', ENVIRONMENT)
    check_collection_target(output, 'native', [native])


def check_collections(output, source):
    check_original_collections(output, source)
    body = prepare_collections(output, source)
    check_collections_chez(output, body)
    exports = [word for name in COLLECTION_EXPORTS for word in ['--export', name]]
    execute([ROOT / 'scripts/build-strict', *exports, output / 'collections.scm', output / 'collections.wasm'],
            output / 'strict-build.json', ENVIRONMENT)
    check_collections_targets(output)


# ---- The new Chez boundary reuses the complete shared writer fixture ----


def check_chez_output(output):
    writer = runpy.run_path(str(ROOT / 'scripts/test-strict-write'))
    cases = writer['cases']()
    fixture = (ROOT / 'tests/strict-write/output.scm').read_text().split('\n', 1)[1]
    actions = [('stream', f'(unless (and (= (copy-output) {len(cases)}) (roundtrip)) (unreachable))'),
               ('graphs', '(graphs)'), ('deep', '(deep-output)'), ('stdout', '(stdout-check)'),
               ('closed', '(closed-empty)'), ('trap', '(callback-trap)'),
               ('character', '(invalid-character)'), ('handle', '(invalid-handle)'),
               ('read-stdout', '(read-stdout)'), ('stdout-failure', '(stdout-failure)')]
    for index, (name, action) in enumerate(actions):
        directory = output / name
        directory.mkdir()
        (directory / 'input.scm').write_text('\n'.join(row[0] for row in cases) + '\n')
        path = directory / 'program.chez.scm'
        path.write_text('(current-directory ' + json.dumps(str(directory)) + ')\n'
                        + reader_ports.chez_output_program(ROOT, fixture + action + '\n'))
        command = ['scheme', '--script', path]
        if name == 'stdout-failure':
            command = ['python3', '-c', 'import os, sys; os.dup2(os.open("/dev/full", os.O_WRONLY), 1); '
                       'os.execvp(sys.argv[1], sys.argv[1:])', *command]
        record = execute(command, directory / 'run.json', ENVIRONMENT, expected='error' if index >= 4 else 0)
        expected = ('stdout:λ😀 (a "b")\nborrowed:!\n()\n' if name == 'stdout'
                    else 'before trap' if name == 'trap' else '')
        assert record['stdout'] == expected, record
        if index < 4:
            assert not record['stderr'], record
        if index >= 5:
            assert (directory / 'pending.txt').read_bytes() == b'buffered'
        if name == 'stream':
            for file, column in [('written.scm', 1), ('displayed.txt', 2)]:
                assert (directory / file).read_bytes() == ''.join(row[column] + '\n' for row in cases).encode()
        if name == 'graphs':
            assert (directory / 'graphs.txt').read_bytes() == writer['expected_graphs']().encode()
        if name == 'deep':
            assert (directory / 'deep.txt').read_bytes() == ('(#(' * 4096 + 'end' + '))' * 4096 + '\n').encode()
        print('PASS identical writer body under Chez:', name, flush=True)


def check_chez_io_boundary(output):
    scalars = [0, 65279, 13, 10, 127, 128, 2047, 2048, 55295, 57344, 65535, 65536, 955, 128512, 1114111]
    (output / 'scalar-input').write_bytes(''.join(map(chr, scalars)).encode())
    source = output / 'boundary.chez.scm'
    source.write_text('(current-directory ' + json.dumps(str(output)) + ')\n'
                      + (ROOT / 'benchmarks/strict-suite/chez-io.scm').read_text() + '\n'
                      + (ROOT / 'tests/strict-compiler/io-boundary-probe.scm').read_text())
    record = execute(['scheme', '--script', source], output / 'boundary.json', ENVIRONMENT)
    assert record['stdout'] == 'PASS Chez scalar I/O boundary\n' and not record['stderr'], record
    invalid = ['80', 'bf', 'c080', 'c1bf', 'f5808080', 'ff', 'c2', 'e282', 'f09f98',
               'c241', 'e24180', 'f0804180', 'e08080', 'f0808080', 'eda080', 'edbfbf',
               'f4908080', 'f7bfbfbf']
    for index, encoded in enumerate(invalid):
        directory = output / f'malformed-{index}'
        directory.mkdir()
        (directory / 'input').write_bytes(b'A' + bytes.fromhex(encoded))
        path = directory / 'program.chez.scm'
        body = '''(let ((input (open-input-file "input")) (pending (open-output-file "pending")))
  (write-string "buffered" pending)
  (match (read-char input)
    ((character-end) (unreachable))
    ((character-value value) (unless (char=? value #\\A) (unreachable))))
  (write-string "before malformed input\\n")
  (read-char input)
  (write-string "unexpected return\\n"))
'''
        path.write_text('(current-directory ' + json.dumps(str(directory)) + ')\n'
                        + reader_ports.chez_output_program(ROOT, body))
        record = execute(['scheme', '--script', path], directory / 'run.json', ENVIRONMENT, expected='error')
        assert record['stdout'] == 'before malformed input\n', record
        assert 'UTF-8' in record['stderr'], record
        assert (directory / 'pending').read_bytes() == b'buffered'
    print(f'PASS Chez scalar ownership/lookahead and {len(invalid)} terminal malformed UTF-8 cases', flush=True)


# ---- Isolate the chosen map order on the complete original compiler ----


def check_map_order(output, source):
    runner = runpy.run_path(str(ROOT / 'benchmarks/r7rs.py'))
    corpus = ROOT / 'benchmarks/r7rs-benchmarks'
    files = {name: (corpus / name).read_bytes() for name in
             ['src/compiler.scm', 'src/common.scm', 'src/Petite-Chez-prelude.scm']}
    items = compiler_port.tokens(source)
    starts = [item.start() for index, item in enumerate(items)
              if item[0] == 'map' and index and items[index - 1][0] == '(']
    adapted = source
    for start in reversed(starts):
        adapted = adapted[:start] + 'compiler-map' + adapted[start + 3:]
    restored = adapted
    for index in reversed(range(len(starts))):
        start = starts[index] + index * (len('compiler-map') - 3)
        assert restored[start:start + len('compiler-map')] == 'compiler-map'
        restored = restored[:start] + 'map' + restored[start + len('compiler-map'):]
    assert restored == source
    mapping = compiler_port.named_form(compiler_port.representations(), '(define (compiler-map ')
    aliases = """(define compiler-null? null?)
(define compiler-car car)
(define compiler-cdr cdr)
(define compiler-cons cons)
(define (compiler-empty) '())
"""
    data = (corpus / 'inputs/compiler.input').read_bytes()
    collection_order, ordered_forms = adapted, []
    for name in ('set-keep', 'set-map'):
        before = compiler_port.collection_form(collection_order, name)
        [(old, new)] = compiler_port.collection_changes(name)
        after = reader_ports.replace(before, old, new)
        collection_order = reader_ports.replace(collection_order, before, after)
        ordered_forms.append(dict(name=name, before=before, after=after))
    restored_order = collection_order
    for entry in reversed(ordered_forms):
        restored_order = reader_ports.replace(restored_order, entry['after'], entry['before'])
    assert restored_order == adapted
    observations = []
    controls = [('original', source), ('left-map', aliases + mapping + '\n' + adapted),
                ('left-map-and-sets', aliases + mapping + '\n' + collection_order)]
    for name, body in controls:
        working = output / name
        working.mkdir()
        inputs = dict(files, **{'src/compiler.scm': body.encode()})
        program = runner['source_text'](inputs, 'compiler', 'chez')
        path = working / 'program.scm'
        path.write_text(program)
        (working / 'input.txt').write_bytes(data)
        # This source shadows Chez's compile-program. Compile the whole program
        # with the suite's ordinary driver so forward calls bind to its own
        # definition, not the host procedure exposed by a --script top level.
        build, command = runner['chez_commands'](working, str(path))
        reader_ports.record(working, 'build', build, ENVIRONMENT)
        record = reader_ports.record(working, 'canonical', command,
                                     ENVIRONMENT, stdin=data.decode())
        result = runner['parse_result'](record['stdout'], 'chez', 'compiler')
        assert result['status'] == 'ok', result
        observations.append(dict(name=name, source_sha256=hashlib.sha256(program.encode()).hexdigest(),
                                 input_sha256=hashlib.sha256(data).hexdigest(), result=result))
        print('PASS complete compiler map-order control:', name, flush=True)
    (output / 'map-order.json').write_text(json.dumps(dict(
        diagnostic_only=True, typed_compiler_workload=False, count=2000, expected_lines=497,
        map_call_source_offsets=starts, reverse_verified=True, observations=observations,
        set_order_forms=ordered_forms,
        note='Only map/set callback evaluation changes; native pairs isolate the stated ordering choices.'),
        indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--runtime', type=Path)
    mode.add_argument('--map-order', action='store_true')
    mode.add_argument('--chez-output', action='store_true')
    parser.add_argument('--collections', action='store_true', help='check source-derived collections with --runtime')
    args = parser.parse_args()
    if args.collections and not args.runtime:
        parser.error('--collections requires --runtime')
    output = args.output.resolve()
    output.mkdir(parents=True)  # An existing directory is never overwritten.
    if args.map_order:
        check_map_order(output, record_source(output))
        return
    if args.chez_output:
        for name, check in [('writer', check_chez_output), ('boundary', check_chez_io_boundary)]:
            directory = output / name
            directory.mkdir()
            check(directory)
        return
    shutil.copy2(args.runtime, output / 'runtime.wasm')
    (output / 'runtime.json').write_text(json.dumps(dict(source=str(args.runtime.resolve()),
        sha256=hashlib.sha256((output / 'runtime.wasm').read_bytes()).hexdigest()), indent=2) + '\n')
    source = record_source(output)
    if args.collections:
        check_collections(output, source)
        return
    check_original_controls(output, source)
    check_probe(output, 'data-probe', 'data')
    check_probe(output, 'result-probe', 'result')
    check_probe(output, 'result-host-failure', 'result', 'compiler probe ordinary host failure')
    check_probe(output, 'result-no-handler', 'result', 'Internal error, no exception handler at this point')


if __name__ == '__main__':
    main()
