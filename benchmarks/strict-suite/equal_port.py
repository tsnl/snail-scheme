"""Preserve all five enabled Clinger equality workloads and their full inputs."""

import difflib
import json
import re
import shutil
import signal

from data_ports import replace
import browse_port
import matrix_port
import reader_ports


# ---- Typed boundaries around the unchanged constructors and repetitions ----

CONTROL = '''(define-syntax equal-cond
  (syntax-rules (else)
    ((_ (else body ...)) (begin body ...))
    ((_ (test body ...) rest ...) (if test (begin body ...) (equal-cond rest ...)))))
'''
COMMON = '''(define symbol-a (datum-symbol (typed-string->symbol "a")))
(define (equal-zero? n) (= n 0))
(: equal-make-vector (-> I64 Datum Datum))
(define (equal-make-vector count fill) (datum-vector (make-vector count fill)))
(: equal-vector->list (-> Datum Datum))
(define (equal-vector->list value)
  (let ((values (datum-vector-values value)))
    (let loop ((index (vector-length values)) (result (datum-null)))
      (if (= index 0) result
          (loop (- index 1) (datum-cons (vector-ref values (- index 1)) result))))))
(: equal-list-tail (-> Datum I64 Datum))
(define (equal-list-tail value count)
  (if (= count 0) value (equal-list-tail (datum-cdr value) (- count 1))))
'''
CONTRACTS = '''(: make-test-list1 (-> I64 Datum Datum))
(: make-test-tree1 (-> I64 Datum))
(: make-test-list2 (-> I64 (-> Datum) Datum))
(: make-test-tree2 (-> I64 Datum))
(: make-test-tree5 (-> I64 Datum))
(: iterate (-> I64 (-> Bool) Bool))
(: equality-benchmark0 (-> I64 Bool))
(: equality-benchmark1 (-> I64 Bool))
(: equality-benchmark2 (-> I64 Bool))
(: equality-benchmark3 (-> I64 Bool))
(: equality-benchmark4 (-> I64 Bool))
(: equality-benchmark5 (-> I64 (Rest I64) Bool))
(: equality-benchmark5short (-> I64 Bool))
(: equality-benchmarks (-> I64 I64 I64 I64 I64 I64 Bool))
'''
INPUTS = '''(: equal-exact (-> Datum I64))
(define (equal-exact datum)
  (match (datum-number-value datum)
    ((exact-number value) value)
    ((rational-number value) (datum-fail "equal: expected an exact parameter"))
    ((inexact-number value) (datum-fail "equal: expected an exact parameter"))
    ((complex-number real imaginary) (datum-fail "equal: expected an exact parameter"))))
(: read-parameters (-> InputPort (Vector I64)))
(define (read-parameters port)
  (let ((values (make-vector 6 0)))
    (let loop ((index 0))
      (if (= index 6) (begin (read-value! (read port)) values)
          (begin (vector-set! values index (equal-exact (read-value! (read port))))
                 (loop (+ index 1)))))))
(define parameters (call-with-input-file "input.txt" read-parameters))
(define input0 (vector-ref parameters 0))
(define input1 (vector-ref parameters 1))
(define input2 (vector-ref parameters 2))
(define input3 (vector-ref parameters 3))
(define input4 (vector-ref parameters 4))
(define input5 (vector-ref parameters 5))
(: configured-count (-> I64))
(define (configured-count) 1)
(define-extern barrier "benchmark" "barrier" (-> Bool))
(: hide (All (T) (-> I64 T T)))
(define (hide count value) (if (barrier) value (unreachable)))
'''
CALL = '''(equality-benchmarks (hide input0 input0) (hide input0 input1)
  (hide input0 input2) (hide input0 input3) (hide input0 input4) (hide input0 input5))'''
WORKER = '''(let loop ((index 0) (result #f))
  (if (< index count) (loop (+ index 1) ''' + CALL + ''') (if result 1 0)))'''
EDITS = [("'()", '(datum-null)', 5), ("'a", 'symbol-a', 4),
         ('(cons ', '(datum-cons ', 3), ('(cdr x)', '(datum-cdr x)', 1),
         ('(set-cdr! ', '(datum-set-cdr! ', 1), ('(list-tail ', '(equal-list-tail ', 1),
         ('(make-vector ', '(equal-make-vector ', 5), ('(vector->list ', '(equal-vector->list ', 3),
         ('(zero? ', '(equal-zero? ', 5), ('(equal? ', '(datum=? ', 6),
         ('(cond ', '(equal-cond ', 1)]


def adaptation(source):
    adapted = source
    for before, after, count in EDITS:
        adapted = replace(adapted, before, after, count)
    restored = adapted
    for before, after, count in reversed(EDITS):
        restored = replace(restored, after, before, count)
    if restored != source:
        raise ValueError('equal edits did not restore the original kernel')
    return CONTRACTS + adapted, [dict(before=b, after=a, count=n) for b, a, n in EDITS]


def specification(data):
    tokens = re.sub(r';[^\n]*', '', data.decode()).split()
    if len(tokens) != 7 or tokens[-1] not in ('#t', '#f'):
        raise ValueError('equal requires six integers and a read but unused Boolean output')
    parameters = list(map(int, tokens[:6]))
    enabled = next((index for index, value in enumerate(parameters[1:], 1) if value <= 0), 5)
    return dict(name='equal', count=1, inputs=[], parameters=parameters, expected=1,
                setup_barriers=0, barriers_per_iteration=6 + enabled,
                additional_exports=['configured-count'], runtime='scalar-datum-reader',
                predicate='original (eq? result #t); input output is read but unused')


def program(source, driver):
    adapted, _ = adaptation(driver.upstream_kernel(source))
    return ('(import (snail strict) (rename (snail datum) (string->symbol typed-string->symbol)) (snail io) (snail read))\n'
            + CONTROL + COMMON + adapted + INPUTS
            + '(: bench (-> I64 I64))\n(define (bench count) ' + WORKER + ')\n(unit)\n')


# ---- Original Chez and the exact adapted library/workload bodies ----

EXPORTS = '''datum-null datum-cons datum-car datum-cdr datum-set-car! datum-set-cdr!
  datum-pair datum-vector datum-vector-values datum-symbol datum=?
  datum-eq? datum-null? datum-pair? datum-length datum-character datum-boolean'''.split()


def chez_prelude(root):
    return reader_ports.chez_reader(root, [*EXPORTS, ('typed-string->symbol', 'string->symbol')]) + CONTROL + COMMON


def complete_chez_sources(files, upstream, adapted, runner, driver):
    source = runner.source_text(files, 'equal', 'chez')
    replacement = chez_prelude(driver.ROOT) + adapted
    control = replace(source, upstream, replacement)
    if replace(control, replacement, upstream) != source:
        raise ValueError('complete Chez source did not reverse')
    return source, control


def write_sources(files, directory, runner, driver):
    original = files['src/equal.scm'].decode()
    upstream = driver.upstream_kernel(original)
    adapted, edits = adaptation(upstream)
    source, control = complete_chez_sources(files, upstream, adapted, runner, driver)
    for system in ('chez', 'chez-adapted'):
        (directory / system).mkdir()
    for name, text in [('upstream.scm', original), ('upstream-kernel.scm', upstream),
                       ('adapted-kernel.scm', adapted), ('strict.scm', program(original, driver)),
                       ('chez/program.scm', source), ('chez-adapted/program.scm', control)]:
        (directory / name).write_text(text)
    driver.save(directory / 'adaptation-ledger.json', dict(edits=edits, complete_reverse_verified=True))
    (directory / 'chez-adaptation.patch').write_text(''.join(difflib.unified_diff(
        source.splitlines(True), control.splitlines(True), fromfile='original-chez', tofile='adapted-chez')))


# ---- Full inputs and original predicate failures execute before timing ----

def write_inputs(target, data, spec, driver):
    target.mkdir(parents=True)
    (target / 'input.txt').write_bytes(data)
    driver.save(target / 'spec.json', spec)


def compiled_commands(directory, target, tools, driver):
    node = [tools['NODE'], '--disable-warning=ExperimentalWarning', driver.HERE / 'reader-host.mjs']
    return [('raw', [*node, directory / 'raw.wasm', target / 'spec.json']),
            ('optimized', [*node, directory / 'optimized.wasm', target / 'spec.json']),
            ('native', [directory / 'native'])]


def compiled_result(run, spec):
    value = json.loads(run['stdout'])
    expected = dict(result=spec['expected'], barriers=spec['barriers_per_iteration'] * spec['count'],
                    setup_closed=1, worker_closed=0)
    if run['stderr'] or any(value.get(key) != amount for key, amount in expected.items()):
        raise ValueError('equal result, opacity or file lifetime differs')
    return value


def check_compiled(directory, target, spec, tools, environment, driver):
    observations = {}
    for system, command in compiled_commands(directory, target, tools, driver):
        run = reader_ports.record(target, system, command, environment, target)
        observations[system] = compiled_result(run, spec)
    return observations


def chez_result(run, spec):
    name = 'equal:' + ':'.join(map(str, spec['parameters']))
    prefix, suffix = f'Running {name}\n', f'+!CSVLINE!+chez,{name},'
    if spec['expected']:
        number = r'[0-9.eE+\-]+'
        valid = re.fullmatch(re.escape(prefix) + rf'Elapsed time: ({number}) seconds \(({number})\) for '
                             + re.escape(name + '\n' + suffix) + rf'({number})\n', run['stdout'])
        valid = valid and float(valid[1]) == float(valid[3])
    else:
        valid = run['stdout'] == prefix + 'ERROR: returned incorrect result: #f\n' + suffix + 'INCORRECT\n'
    if not valid or run['stderr']:
        raise ValueError('equal complete Chez predicate or output frame differs')
    return dict(correct=bool(spec['expected']))


def check_chez(target, data, spec, commands, environment):
    observations = {}
    for system, command in commands.items():
        run = reader_ports.record(target, system, command, environment, target, data.decode())
        observations[system] = chez_result(run, spec)
    return observations


def validate_input(directory, label, data, accepted, commands, tools, environment, driver):
    target, spec = directory / 'checks' / label, dict(specification(data), expected=accepted)
    write_inputs(target, data, spec, driver)
    observations = check_compiled(directory, target, spec, tools, environment, driver)
    observations.update(check_chez(target, data, spec, commands, environment))
    driver.save(target / 'validation.json', observations)
    return dict(label=label, accepted=bool(accepted), parameters=spec['parameters'], systems=list(observations))


def fixtures(data):
    cases = [('canonical', data, 1), ('small', b'100\n4\n3\n10\n12\n16\n#t\n', 1),
             ('unused-output', b'100\n4\n3\n10\n12\n16\n#f\n', 1)]
    for index in range(1, 6):
        values = [100, 4, 3, 10, 12, 16]
        values[index] = 0
        cases.append((f'zero-phase-{index}', ('\n'.join(map(str, values)) + '\n#t\n').encode(), 0))
    return cases


# ---- Separate full-size shape and call-count observations ----

SHAPES = '''(: shared-spine? (-> Datum I64 Datum Bool))
(define (shared-spine? values count child)
  (if (= count 0) (datum-null? values)
      (and (datum-pair? values) (datum-eq? (datum-car values) child)
           (shared-spine? (datum-cdr values) (- count 1) child))))
(: shared-shape (-> Datum I64 I64))
(define (shared-shape value height)
  (if (= height 0) (if (datum-null? value) 0 -1000000)
      (if (shared-spine? value height (datum-car value))
          (+ height (shared-shape (datum-car value) (- height 1))) -1000000)))
(: unshared-spine (-> Datum I64 I64 Datum I64))
(define (unshared-spine values remaining height previous)
  (if (= remaining 0) (if (datum-null? values) 0 -1000000)
      (let ((child (datum-car values)))
        (if (and (> height 1) (datum-eq? child previous)) -1000000
            (+ (+ 1 (unshared-shape child (- height 1)))
               (unshared-spine (datum-cdr values) (- remaining 1) height child))))))
(: unshared-shape (-> Datum I64 I64))
(define (unshared-shape value height)
  (if (= height 0) (if (datum-null? value) 0 -1000000)
      (unshared-spine value height height (datum-null))))
(: deep-shape? (-> Datum I64 Bool))
(define (deep-shape? value count)
  (if (= count 0) (datum-null? value)
      (and (datum-pair? value) (datum-eq? (datum-cdr value) symbol-a)
           (deep-shape? (datum-car value) (- count 1)))))
(: flat-shape? (-> Datum I64 Bool))
(define (flat-shape? value count)
  (let ((values (datum-vector-values value)))
    (and (= (vector-length values) count)
         (let loop ((index 0))
           (or (= index count)
               (and (datum-eq? (vector-ref values index) symbol-a) (loop (+ index 1))))))))
(: full-shapes? (-> Bool))
(define (full-shapes?)
  (let* ((shared (make-test-tree1 100)) (unshared (make-test-tree2 8))
         (flat (equal-make-vector 1000 symbol-a))
         (shallow (equal-vector->list (equal-make-vector 2000 (make-test-tree2 3))))
         (deep (make-test-tree5 5000)))
    (and (= (shared-shape shared 100) 5050) (= (unshared-shape unshared 8) 109600)
         (flat-shape? flat 1000) (shared-spine? shallow 2000 (datum-car shallow))
         (= (unshared-shape (datum-car shallow) 3) 15) (deep-shape? deep 5000))))
'''
COUNTERS = '''(define observed-phase (ref 0))
(define forced-false-phase (ref -1))
(define observed-calls (make-vector 6 0))
(: make-observed-difference! (-> Datum I64 Unit))
(define (make-observed-difference! right phase)
  (when (= phase (ref-get forced-false-phase))
    (if (= phase 3) (vector-set! (datum-vector-values right) 0 (datum-boolean #f))
        (datum-set-car! right (datum-boolean #f)))))
(: observed-equal? (-> Datum Datum Bool))
(define (observed-equal? left right)
  (let ((phase (ref-get observed-phase)))
    (vector-set! observed-calls phase (+ (vector-ref observed-calls phase) 1))
    (make-observed-difference! right phase))
  (datum=? left right))
(: canonical-calls? (-> Bool))
(define (canonical-calls?)
  (and (= (vector-ref observed-calls 0) 0) (= (vector-ref observed-calls 1) 100)
       (= (vector-ref observed-calls 2) 8) (= (vector-ref observed-calls 3) 1000)
       (= (vector-ref observed-calls 4) 2000) (= (vector-ref observed-calls 5) 5000)))
(: clear-observed-calls! (-> Unit))
(define (clear-observed-calls!)
  (let loop ((index 0))
    (if (= index 6) (unit)
        (begin (vector-set! observed-calls index 0) (loop (+ index 1))))))
(: prefix-calls? (-> I64 Bool))
(define (prefix-calls? phase)
  (let loop ((index 0))
    (or (= index 6)
        (and (= (vector-ref observed-calls index) (if (and (> index 0) (<= index phase)) 1 0))
             (loop (+ index 1))))))
(: negative-equality-phases? (-> Bool))
(define (negative-equality-phases?)
  (let loop ((phase 1))
    (if (= phase 6) (begin (ref-set! forced-false-phase -1) #t)
        (begin (clear-observed-calls!) (ref-set! forced-false-phase phase)
               (and (not (equality-benchmarks 1 1 1 1 1 1))
                    (prefix-calls? phase) (loop (+ phase 1)))))))
'''
PROBE_BODY = '''(if (and (full-shapes?) (= ''' + WORKER + ''' 1) (canonical-calls?)
                        (negative-equality-phases?)
                        (equality-benchmark0 17) (= (vector-ref observed-calls 0) 17)) 42 0)'''


def observed_kernel(kernel, adapted):
    token = '(datum=? ' if adapted else '(equal? '
    kernel = replace(kernel, token, '(observed-equal? ', 6)
    for phase in range(6):
        prefix = f'(define (equality-benchmark{phase} n' + (' . rest)' if phase == 5 else ')')
        kernel = replace(kernel, prefix, prefix + f'\n  (ref-set! observed-phase {phase})')
    return kernel


def strict_probe(source, driver):
    kernel = adaptation(driver.upstream_kernel(source))[0]
    original = program(source, driver)
    modified = replace(original, kernel, COUNTERS + observed_kernel(kernel, True) + SHAPES)
    return replace(modified, '(define (bench count) ' + WORKER + ')', '(define (bench count) ' + PROBE_BODY + ')')


ORIGINAL_ALIASES = '''(define datum-cons cons)
(define datum-car car)
(define datum-cdr cdr)
(define datum-set-car! set-car!)
(define datum-boolean values)
(define datum-null? null?)
(define datum-pair? pair?)
(define datum-eq? eq?)
(define datum=? equal?)
(define (datum-null) '())
(define datum-vector values)
(define datum-vector-values values)
(define datum-symbol values)
(define equal-make-vector make-vector)
(define equal-vector->list vector->list)
(define symbol-a 'a)
'''


def chez_probe(source, adapted, root, driver):
    kernel = driver.upstream_kernel(source)
    prefix = chez_prelude(root) if adapted else reader_ports.CHEZ_TYPES + ORIGINAL_ALIASES
    kernel = adaptation(kernel)[0] if adapted else kernel
    inputs = ''.join(f'(define input{index} (read))\n' for index in range(6))
    return ('(import (chezscheme))\n' + prefix + COUNTERS + observed_kernel(kernel, adapted) + SHAPES
            + inputs + '(read)\n(define (hide count value) value)\n(define count 1)\n'
            + '(write ' + PROBE_BODY + ') (newline)\n')


def build_observation(directory, source, data, tools, environment, driver):
    target = directory / 'observations'
    spec = dict(specification(data), expected=42, barriers_per_iteration=27)
    write_inputs(target, data, spec, driver)
    (target / 'strict.scm').write_text(strict_probe(source, driver))
    reader_ports.build(target, tools, environment, driver)
    return target, spec


def check_chez_observations(target, source, data, tools, environment, driver):
    observations = {}
    for adapted, system in [(False, 'chez'), (True, 'chez-adapted')]:
        (target / (system + '.scm')).write_text(chez_probe(source, adapted, driver.ROOT, driver))
        run = reader_ports.record(target, system, [tools['CHEZ'], '--script', target / (system + '.scm')],
                                  environment, stdin=data.decode())
        if run['stdout'] != '42\n' or run['stderr']:
            raise ValueError('equal Chez shape or iteration observation failed: ' + system)
        observations[system] = dict(result=42)
    return observations


def validate_observations(directory, data, tools, environment, driver):
    source = (directory / 'upstream.scm').read_text()
    target, spec = build_observation(directory, source, data, tools, environment, driver)
    observations = check_compiled(target, target, spec, tools, environment, driver)
    observations.update(check_chez_observations(target, source, data, tools, environment, driver))
    driver.save(target / 'validation.json', dict(observations=observations,
        shared_pair_occurrences=5050, unshared_pair_occurrences=109600, vector_length=1000,
        shallow_spine=2000, shallow_shared_subtree_pairs=15, deep_car_chain=5000,
        canonical_equality_calls=[0, 100, 8, 1000, 2000, 5000], separate_cyclic_case_calls=17,
        negative_equality_phases=5, sharing_argument='complete shared-spine identity observations; '
        'unshared occurrence counts and adjacent sibling distinction supplement the unchanged recursive '
        'construction and datum-cons allocation of two fresh Ref cells on every call'))


def prepare_case(files, output, runner, tools, environment, driver):
    previous = signal.signal(signal.SIGTERM, reader_ports.interrupted)
    try:
        return prepare_workload(files, output, runner, tools, environment, driver)
    finally:
        signal.signal(signal.SIGTERM, previous)


def prepare_workload(files, output, runner, tools, environment, driver):
    directory = output / 'equal'
    data = files['inputs/equal.input']
    spec = specification(data)
    write_inputs(directory, data, spec, driver)
    write_sources(files, directory, runner, driver)
    reader_ports.build(directory, tools, environment, driver)
    commands = reader_ports.build_chez(directory, runner, tools, environment)
    validate_workload(directory, data, commands, tools, environment, driver)
    prepare_controls(directory, directory / 'controls', tools, environment, driver)
    return dict(name='equal', status='ready', spec=spec, chez_commands=commands,
                systems=['strict', 'native', 'chez', 'chez-adapted'],
                hashes={str(path.relative_to(directory)): driver.digest(path)
                        for path in directory.rglob('*') if path.is_file()})


def validate_workload(directory, data, commands, tools, environment, driver):
    checks = [validate_input(directory, label, source, accepted, commands, tools, environment, driver)
              for label, source, accepted in fixtures(data)]
    driver.save(directory / 'canonical-validation.json', checks)
    browse_port.validate_datum_units(directory, tools, environment, driver)
    validate_observations(directory, data, tools, environment, driver)


# ---- Rust is an unchanged Rc/pointer-hash algorithm and layout control ----

def retain_rust_source(target, driver):
    source = driver.ROOT / 'benchmarks/wasm-reference'
    shutil.copytree(source / 'src', target / 'src')
    for name in ('Cargo.toml', 'Cargo.lock', 'run-wasi.mjs'):
        shutil.copy2(source / name, target / name)


def check_rust_input(target, case, tools, environment):
    label, data, accepted = case
    checks = []
    for system, command in reader_ports.rust_commands(target, 'equal', tools):
        run = reader_ports.record(target, label + '-' + system, command, environment,
                                  stdin=data.decode(), failure=not accepted)
        rust_result(run, accepted)
        checks.append(dict(label=label, system=system, accepted=bool(accepted)))
    return checks


def rust_result(run, accepted):
    if accepted:
        valid = re.fullmatch(r'Result: #t\n\+!CSVLINE!\+rust-wasm,equal:1,[0-9.eE+\-]+\n', run['stdout'])
        valid = valid and not run['stderr']
    else:
        valid = not run['stdout'] and 'assertion failed: result' in run['stderr']
    if not valid:
        raise ValueError('Rust equality result frame or false-aggregate rejection differs')


def prepare_rust_control(original, target, tools, environment, driver):
    retain_rust_source(target, driver)
    reader_ports.record(target, 'unit-tests', [tools['CARGO'], 'test', '--offline', '--bin', 'equal'],
                        dict(environment, CARGO_TARGET_DIR=str(target / 'target')), target)
    reader_ports.build_rust_bin(target, 'equal', tools, environment)
    checks = []
    for case in fixtures((original / 'input.txt').read_bytes()):
        checks.extend(check_rust_input(target, case, tools, environment))
    driver.save(target / 'validation.json', dict(checks=checks,
        source_sha256=driver.digest(target / 'src/bin/equal.rs'),
        representation='unchanged immutable Rc pairs/vectors, char atoms, pointer-pair HashSet, '
                       'explicit work vector and iterative Drop; distinct constructors, roots, '
                       'allocation layout and destruction from strict Scheme'))


def prepare_controls(original, target, tools, environment, driver):
    target.mkdir()
    browse_port.prepare_native_control(original, target / 'native', tools, environment, driver)
    validate_native_lifetime(original, target / 'lifetime', tools, environment, driver)
    prepare_rust_control(original, target / 'rust', tools, environment, driver)
    matrix_port.retain_toolchain(target, tools, environment, driver)
    driver.save(target / 'prepared.json', dict(status='ready',
        hashes={str(path.relative_to(target)): driver.digest(path)
                for path in target.rglob('*') if path.is_file()}))


# ---- A separate collector probe checks post-return live footprint ----


def lifetime_entry():
    entry = reader_ports.NATIVE_ENTRY.replace('#include <stdlib.h>',
        '#include <stdlib.h>\nextern void native_gc_collect(void);')
    entry = replace(entry, 'int64_t result = bench(count);',
                    'native_gc_collect();\n    int64_t result = bench(count);\n    native_gc_collect();')
    return replace(entry, 'int64_t count = configured_count();',
                   'int64_t count = argc > 1 ? 0 : configured_count();')


def build_lifetime_probe(original, target, environment, driver):
    target.mkdir()
    (target / 'entry.c').write_text(lifetime_entry())
    shutil.copy2(original / 'native-provider.h', target / 'native-provider.h')
    shutil.copy2(original / 'input.txt', target / 'input.txt')
    reader_ports.record(target, 'build', [driver.ROOT / 'scripts/build-native', '--wasm', '--c-provider', 'benchmark',
        original / 'native-provider.h', original / 'native-provider.c', '--entry-c', target / 'entry.c',
        original / 'strict-native.wasm', target / 'native'], environment, driver.ROOT)


def validate_native_lifetime(original, target, tools, environment, driver):
    build_lifetime_probe(original, target, environment, driver)
    configured = dict(environment, SNAIL_GC_STATS='1', SNAIL_GC_HEAP_BYTES=str(256 * 1024 * 1024),
                      SNAIL_GC_MIN_BYTES=str(64 * 1024))
    baseline = collection_observation(target, 'setup-only', ['setup-only'], configured)
    full = collection_observation(target, 'full-workload', [], configured)
    if (full['result']['result'] != 1 or full['result']['barriers'] != 11 or full['gc']['collections'] <= 2
            or any(full['gc'][key] != baseline['gc'][key] for key in ('last_live', 'live_objects'))):
        raise ValueError('full equality traversal failed or left an unexpected post-return live footprint')
    driver.save(target / 'validation.json', dict(baseline=baseline, full=full,
        condition='forced collection after full bench returns matches setup-only live bytes and object count',
        interpretation='no additional post-return live footprint relative to setup; aggregate bytes/count '
                       'do not identify each surviving object or measure equal allocation/peak usage'))


def collection_observation(target, label, arguments, environment):
    run = reader_ports.record(target, label, [target / 'native', *arguments], environment)
    stats = {name: int(amount) for name, amount in re.findall(r'(\w+)=(\d+)(?: |$)', run['stderr'])}
    result = json.loads(run['stdout'])
    if result['setup_closed'] != 1 or result['worker_closed'] != 0:
        raise ValueError('collection probe changed file lifetime')
    if arguments and (result['result'] != 0 or result['barriers'] != 0 or stats['collections'] != 2):
        raise ValueError('setup-only collection baseline executed the workload')
    return dict(result=result, gc=stats)
