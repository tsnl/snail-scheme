"""Keep Ray's complete scene traversal and text-file lifecycle in Scheme."""

import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import shutil
import struct

from data_ports import form, replace
from string_port import exact_json_integer, i64


# ---- Concrete geometry and the two possible runner results ----

IMAGE_SHA256 = '38babccc4583f44c18d17488314bffe9723a0fd2bdeff7227ec0d7ed1ea1463d'
PIXELS_SHA256 = '2504547e212cb609b776f06ac18c74915dac54a988e42f9584d0509c03f044eb'
STRICT_TYPES = '''(define-data Point
  (make-point (x F64 point-x) (y F64 point-y) (z F64 point-z)))
(define-data Sphere
  (make-sphere (color F64 sphere-color) (radius F64 sphere-radius)
               (center Point sphere-center)))
(define-data Root (no-root) (some-root (value F64 root-value)))
(define-data Candidate (no-point) (some-point (value Point candidate-point)))
(define-data Hit (miss) (hit (sphere Sphere hit-sphere) (point Point hit-point)))
(: root? (-> Root Bool))
(define (root? value) (match value ((no-root) #f) ((some-root n) #t)))
(: candidate? (-> Candidate Bool))
(define (candidate? value) (match value ((no-point) #f) ((some-point p) #t)))
(: hit? (-> Hit Bool))
(define (hit? value) (match value ((miss) #f) ((hit s p) #t)))
'''
CHEZ_TYPES = '''(define-syntax : (syntax-rules () ((_ . signature) (begin))))
(define-syntax ann (syntax-rules () ((_ value type) value)))
(define (make-point x y z) (vector x y z))
(define (point-x p) (vector-ref p 0))
(define (point-y p) (vector-ref p 1))
(define (point-z p) (vector-ref p 2))
(define (make-sphere color radius center) (vector color radius center))
(define (sphere-color s) (vector-ref s 0))
(define (sphere-radius s) (vector-ref s 1))
(define (sphere-center s) (vector-ref s 2))
(define (no-root) (vector 0))
(define (some-root value) (vector 1 value))
(define (root? value) (= (vector-ref value 0) 1))
(define (root-value value) (vector-ref value 1))
(define (no-point) (vector 0))
(define (some-point value) (vector 1 value))
(define (candidate? value) (= (vector-ref value 0) 1))
(define (candidate-point value) (vector-ref value 1))
(define (miss) (vector 0))
(define (hit sphere point) (vector 1 sphere point))
(define (hit? value) (= (vector-ref value 0) 1))
(define (hit-sphere value) (vector-ref value 1))
(define (hit-point value) (vector-ref value 2))
(define (ref value) (vector value))
(define (ref-get cell) (vector-ref cell 0))
(define (ref-set! cell value) (vector-set! cell 0 value))
(define i64->f64 inexact)
(define f64->i64 exact)
'''
CHEZ_FORMAT = '''(define (write-i64 number port)
  (when (< number 0) (write-char #\\- port))
  (write-negative-digits (if (> number 0) (- 0 number) number) port))
(define (write-negative-digits number port)
  (let ((prefix (quotient number 10)))
    (unless (= prefix 0) (write-negative-digits prefix port))
    (write-char (integer->char (- 48 (remainder number 10))) port)))
'''
# Chez ports already carry their resource identity. Keep these boundary aliases
# local: Ray's ordinary ref-get still reads its explicit vector-backed cells.
CHEZ_PORT_IMPORT = ('(only (chezscheme)\n    current-time',
                    '(only (chezscheme)\n    port-closed?\n    current-time')
CHEZ_WRITE_STRING = '''(define write-string
  (let ((output-handle values) (ref-get values))
    (define (port-check-output port)
      (unless (and (output-port? port) (not (port-closed? port)))
        (error 'write-string "expected an open output port")))
    (define (write-string-to text port)
      ;; Even an empty write checks direction and lifetime without emitting text.
      (port-check-output (ref-get (output-handle port)))
      (let ((count (string-length text)))
        (let loop ((index 0))
          (unless (= index count)
            (write-char (string-ref text index) port)
            (loop (+ index 1))))))
    write-string-to))'''
ORIGINAL_WRITE_STRING = '''(define write-string
  (case-lambda
    ((string)
      (put-string (current-output-port) string))
    ((string port)
      (put-string port string))
    ((string port start)
      (put-string port string start))
    ((string port start end)
      (put-string port string start (fx+ (fx- end start) 1)))))'''
COMMON = ''';; Chez min/max propagate NaN and select the right equal operand,
;; including signed zero. The source uses these two-argument operations only.
(: ray-min (-> F64 F64 F64))
(define (ray-min left right)
  (if (not (= left left)) left (if (< left right) left right)))
(: ray-max (-> F64 F64 F64))
(define (ray-max left right)
  (if (not (= left left)) left (if (> left right) left right)))
'''
CONTRACTS = '''(: sq (-> F64 F64))
(: mag (-> F64 F64 F64 F64))
(: unit-vector (-> F64 F64 F64 Point))
(: distance (-> Point Point F64))
(: minroot (-> F64 F64 F64 Root))
(: tracer (-> String I64 Unit))
(: color-at (-> F64 F64 I64))
(: sendray (-> Point Point F64))
(: first-hit (-> Point Point Hit))
(: lambert (-> Sphere Point Point F64))
(: defsphere (-> F64 F64 F64 F64 F64 Sphere))
(: surface-color (-> Sphere F64))
(: intersect (-> Sphere Point Point Candidate))
(: sphere-intersect (-> Sphere Point Point Candidate))
(: normal (-> Sphere Point Point))
(: sphere-normal (-> Sphere Point Point))
(: ray-test (-> I64 String Unit))
(: run (-> I64 String I64))
'''
INPUTS = '''(define-extern path-length "benchmark" "path_length" (-> I64))
(define-extern path-character "benchmark" "path_character" (-> I64 Char))
(: input-path (-> String))
(define (input-path)
  (let* ((size (path-length)) (text (make-string size #\\space)))
    (let loop ((index 0))
      (if (= index size) text
          (begin (string-set! text index (path-character index)) (loop (+ index 1)))))))
(define input0 (native-input-i64 (ann 0 I32)))
(define input1 (input-path))
(define expected-kind (native-input-i64 (ann 1 I32)))
(: hide-path (-> I64 String String))
(define (hide-path count value) (if (barrier) value (unreachable)))
'''
WORKER = '''(let loop ((i 0) (result 0))
  (if (< i count)
      (loop (+ i 1) (run (hide count input0) (hide-path count input1)))
      (if (= result expected-kind) 1 0)))'''


INPUT_DECODER = '''(import (chezscheme))
(let* ((count (read)) (resolution (read)) (pathname (read)) (expected (read)))
  (unless (and (integer? count) (exact? count) (integer? resolution) (exact? resolution) (string? pathname)
               (eof-object? (read)))
    (error 'ray-input "expected count, integral resolution, pathname and result"))
  (write count) (newline) (write resolution) (newline)
  (write (cond ((eq? expected #f) 0) ((eq? expected 'ok) 1) (else 2))) (newline)
  (string-for-each (lambda (character) (write (char->integer character)) (display " ")) pathname)
  (newline))
'''


def specification(data):
    # Use the actual Scheme reader before timing: escaped symbols, booleans,
    # strings and compound wrong expectations must retain their original meaning.
    with tempfile.TemporaryDirectory(prefix='snail-ray-input-') as temporary:
        decoder = Path(temporary) / 'decode.scm'
        decoder.write_text(INPUT_DECODER)
        record = subprocess.run([os.environ.get('CHEZ', 'scheme'), '--script', decoder],
                                input=data, capture_output=True, check=True)
    count, resolution, kind, characters = record.stdout.decode().splitlines()
    return dict(name='ray', count=exact_json_integer(i64(count)),
                inputs=[exact_json_integer(i64(resolution)), int(kind)],
                pathname=''.join(map(chr, map(int, characters.split()))),
                expected=1, barriers_per_iteration=2,
                setup_barriers=0, runtime='scalar-io', image_sha256=IMAGE_SHA256)


# ---- Reversible edits expose every representation and arithmetic change ----

FIRST_HIT = '''(define (first-hit pt ray)
  (let loop ((lst (ref-get *world*)) (selected (miss)) (dist 1e308))
    (if (null? lst)
        selected
        (let ((s (car lst)))
          (let ((candidate (intersect s pt ray)))
            (if (candidate? candidate)
                (let* ((h (candidate-point candidate)) (d (distance h pt)))
                  (if (< d dist)
                      (loop (cdr lst) (hit s h) d)
                      (loop (cdr lst) selected dist)))
                (loop (cdr lst) selected dist)))))))'''
SENDRAY = '''(define (sendray pt ray)
  (let ((selected (first-hit pt ray)))
    (if (hit? selected)
        (* (lambert (hit-sphere selected) (hit-point selected) ray)
           (surface-color (hit-sphere selected)))
        0.0)))'''


def adaptation(source):
    edits = []

    def edit(old, new, count=1):
        nonlocal source
        source = replace(source, old, new, count)
        edits.append(dict(before=old, after=new, count=count))

    for name in ('make-point', 'point-x', 'point-y', 'point-z',
                 'make-sphere', 'sphere-color', 'sphere-radius', 'sphere-center'):
        edit(form(source, '(define (' + name + ' '), '; ' + name + ': concrete product operation.')
    edit(form(source, '(define (first-hit '), FIRST_HIT)
    edit(form(source, '(define (sendray '), SENDRAY)
    edit("(define *world* '())", "(define *world* (ref (ann '() (List Sphere))))")
    edit('(set! *world* (cons s *world*))', '(ref-set! *world* (cons s (ref-get *world*)))')
    edit("(set! *world* '())", "(ref-set! *world* '())")
    edit('(zero? a)', '(= a 0.0)')
    edit('(negative? disc)', '(< disc 0.0)')
    edit('(/ (- c) b)', '(some-root (/ (* -1.0 c) b))')
    edit('            #f\n', '            (no-root)\n')
    edit('(- b)', '(* -1.0 b)')
    edit('(* 4.0 a c)', '(* (* 4.0 a) c)')
    edit('(min (/ (+ minus-b discrt) two-a)\n                   (/ (- minus-b discrt) two-a))',
         '(some-root (ray-min (/ (+ minus-b discrt) two-a)\n                              (/ (- minus-b discrt) two-a)))')
    edit('(+ (sq x) (sq y) (sq z))', '(+ (+ (sq x) (sq y)) (sq z))')
    edit('(+ (sq xr) (sq yr) (sq zr))', '(+ (+ (sq xr) (sq yr)) (sq zr))')
    edit('''(+ (* (- (point-x pt) (point-x c)) xr)
                   (* (- (point-y pt) (point-y c)) yr)
                   (* (- (point-z pt) (point-z c)) zr))''',
         '''(+ (+ (* (- (point-x pt) (point-x c)) xr)
                      (* (- (point-y pt) (point-y c)) yr))
                   (* (- (point-z pt) (point-z c)) zr))''')
    edit('''(+ (sq (- (point-x pt) (point-x c)))
                (sq (- (point-y pt) (point-y c)))
                (sq (- (point-z pt) (point-z c)))
                (- (sq (sphere-radius s))))''',
         '''(+ (+ (+ (sq (- (point-x pt) (point-x c)))
                      (sq (- (point-y pt) (point-y c))))
                   (sq (- (point-z pt) (point-z c))))
                (* -1.0 (sq (sphere-radius s))))''')
    edit('''(if n
        (make-point (+ (point-x pt) (* n xr))
                    (+ (point-y pt) (* n yr))
                    (+ (point-z pt) (* n zr)))
        #f)''',
         '''(if (root? n)
        (let ((root (root-value n)))
          (some-point (make-point (+ (point-x pt) (* root xr))
                                  (+ (point-y pt) (* root yr))
                                  (+ (point-z pt) (* root zr)))))
        (no-point))''')
    edit('''(max 0.0
         (+ (* (point-x ray) (point-x n))
            (* (point-y ray) (point-y n))
            (* (point-z ray) (point-z n))))''',
         '''(ray-max 0.0
         (+ (+ (* (point-x ray) (point-x n))
               (* (point-y ray) (point-y n)))
            (* (point-z ray) (point-z n))))''')
    edit('(- (point-z eye))', '(* -1.0 (point-z eye))')
    for old, new, count in (('(inexact ', '(i64->f64 ', 6), ('(exact ', '(f64->i64 ', 1),
                            ('(display ', '(write-string ', 3), ('(write ', '(write-i64 ', 3), ("  'ok)", '  1)', 1)):
        edit(old, new, count)
    restored = source
    for step in reversed(edits):
        restored = replace(restored, step['after'], step['before'], step['count'])
    return source, edits, restored


def kernel(source):
    adapted, _, restored = adaptation(source)
    if restored != source:
        raise ValueError('Ray source edits did not restore the complete original kernel')
    return CONTRACTS + adapted


def control_prelude(source):
    source = replace(source, '(import (snail strict))', '(import (snail strict) (snail io))')
    return replace(source, '(define-syntax do\n  (syntax-rules ()\n',
                   '(define-syntax do\n  (syntax-rules ()\n'
                   '    ((_ ((var init step) ...) (test) body ...)\n'
                   '     (do ((var init step) ...) (test (unit)) body ...))\n')


def adapt_chez_harness(source, reverse=False):
    edits = (CHEZ_PORT_IMPORT, (ORIGINAL_WRITE_STRING, CHEZ_WRITE_STRING), ('(result #f)', '(result 0)'),
             ('(ok? result)', "(ok? (if (= result 0) #f 'ok))"),
             ('(write result)', "(write (if (= result 0) #f 'ok))"))
    for before, after in edits:
        source = replace(source, after if reverse else before, before if reverse else after)
    return source


# ---- File checks happen after the complete original predicate and timer ----

def output_path(directory, spec):
    return directory / spec['pathname']


def reset_output(directory, spec):
    output = output_path(directory, spec)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.unlink(missing_ok=True)


def check_image(directory, spec):
    data = output_path(directory, spec).read_bytes()
    checksum = hashlib.sha256(data).hexdigest()
    if checksum != spec['image_sha256']:
        raise ValueError('Ray complete image bytes differ from the original Chez oracle')
    words = data.split()
    if words[:4] != [b'P2', b'100', b'100', b'255'] or len(words) != 10004:
        raise ValueError('Ray image must contain the complete original 100 by 100 pixel grid')
    if hashlib.sha256(bytes(map(int, words[4:]))).hexdigest() != PIXELS_SHA256:
        raise ValueError('Ray image differs from the established upstream pixel checksum')
    return dict(bytes=len(data), sha256=checksum, pixels_sha256=PIXELS_SHA256)


# ---- Reuse the existing Rust provider and its scalar-only linker ----

def build_runtime(directory, tools, environment, driver):
    driver.freeze_fft_toolchain(directory, tools['RUSTC'], environment, prefix='runtime')
    command = [tools['CARGO'], 'rustc', '--crate-type=cdylib', '--quiet', '--offline',
               '--release', '--target', 'wasm32-wasip1', '--manifest-path', driver.ROOT / 'Cargo.toml',
               '--target-dir', driver.ROOT / 'build/wasm-runtime']
    record = driver.execute(command, driver.ROOT, environment)
    driver.save(directory / 'runtime-build.json', record)
    driver.require_success(record)
    shutil.copyfile(driver.ROOT / 'build/wasm-runtime/wasm32-wasip1/release/snail_runtime.wasm',
                    directory / 'runtime.wasm')
    (directory / 'input-decoder.scm').write_text(INPUT_DECODER)


def link_runtime(directory, tools, environment, driver):
    # Keep the compiled Scheme inputs and all merge/pruning intermediates.
    for suffix in ('', '.raw.wasm'):
        output = directory / ('strict.wasm' + suffix)
        source = directory / ('strict-native.wasm' + suffix)
        output.rename(source)
        command = [driver.ROOT / 'scripts/link-strict-runtime', '--runtime', directory / 'runtime.wasm']
        flags = ['--diagnostic-prune-only'] if suffix else []
        record = driver.execute(command + flags + [source, output], driver.ROOT, environment)
        driver.save(directory / ('runtime-link' + ('-raw' if suffix else '') + '.json'), record)
        driver.require_success(record)


def validate_outputs(directory, runner, tools, environment, driver):
    original = driver.upstream_kernel((directory / 'upstream.scm').read_text())
    _, edits, restored = adaptation(original)
    driver.save(directory / 'reversible-source-edits.json', dict(edits=edits, restored_original=restored == original))
    check_formatter_source(driver)
    validate_images(directory, runner, tools, environment, driver)
    validate_geometry(directory, runner, tools, environment, driver)
    spec = driver.load(directory / 'spec.json')
    for target in (directory, directory / 'same-source-chez'):
        output_path(target, spec).unlink(missing_ok=True)


# ---- Separate viewport and predicate probes keep canonical artifacts intact ----

def viewport_source(source):
    return replace(source, '(extent (* res 100))', '(extent probe-extent)')


def build_viewports(directory, runner, tools, environment, driver):
    target = directory / 'viewport-probes'
    target.mkdir()
    spec = driver.load(directory / 'spec.json')
    driver.save(target / 'spec.json', dict(spec, inputs=spec['inputs'] + [7]))
    shutil.copyfile(directory / 'runtime.wasm', target / 'runtime.wasm')
    source = viewport_source((directory / 'strict.scm').read_text())
    source = replace(source, '(define input0 ', '(define probe-extent (native-input-i64 (ann 2 I32)))\n(define input0 ')
    (target / 'strict.scm').write_text(source)
    driver.build_strict(target, tools, environment)
    for system in ('original', 'adapted'):
        control = target / system
        control.mkdir()
        origin = directory if system == 'original' else directory / 'same-source-chez'
        source = viewport_source((origin / 'program.scm').read_text())
        source = replace(source, '(define eye ', '(define probe-extent (read))\n(define eye ')
        (control / 'program.scm').write_text(source)
        driver.build_chez(control, runner, environment, 'build.json')
    return target


def image_cases():
    cases = [dict(label=f'image-{extent}-resolution-{resolution}', count=count, extent=extent,
                  resolution=resolution, expected='ok', existing=existing)
             for extent, resolution, count, existing in ((0, 0, 1, False), (1, 1, 1, False),
                 (7, 1, 2, True), (7, 2, 1, False), (7, 3, 2, False))]
    cases.append(dict(label='unicode-path', count=2, extent=3, resolution=1,
                      expected='ok', existing=True, pathname='outputs/λ😀.pgm'))
    for count in (-1, 0, 2):
        for index, expected in enumerate(('#f', 'ok', 'wrong', '0', '1', '"ok"', '(ok)', '|ok|', '#false', '#t')):
            cases.append(dict(label=f'predicate-{count}-{index}', count=count, extent=2,
                              resolution=1, expected=expected, existing=True))
    return cases


def probe_input(case):
    pathname = json.dumps(case.get('pathname', 'outputs/ray.output'), ensure_ascii=False)
    return f'{case["count"]}\n{case["resolution"]}\n{pathname}\n{case["expected"]}\n'


def seed_probe(target, spec, existing):
    reset_output(target, spec)
    if existing:
        output_path(target, spec).write_bytes(b'old file must be replaced\n' * 100)


def validate_image_case(target, case, runner, tools, environment, driver):
    data = probe_input(case)
    spec = specification(data.encode())
    accepted = (1 if case['count'] > 0 else 0) == spec['inputs'][1]
    spec.update(inputs=spec['inputs'] + [case['extent']], expected=int(accepted), trace=True)
    specfile = target / (case['label'] + '.json')
    driver.save(specfile, spec)
    records, images = [], []
    for system in ('original', 'adapted', 'raw', 'optimized'):
        cwd = target / system if system in ('original', 'adapted') else target
        seed_probe(cwd, spec, case['existing'])
        if system in ('original', 'adapted'):
            command = [tools['CHEZ'], '--program', cwd / 'program.so']
            record = driver.execute(command, cwd, environment, stdin=str(case['extent']) + '\n' + data)
            driver.require_success(record)
            actual = runner.parse_result(record['stdout'], 'chez', 'ray')['status'] == 'ok'
            if actual != accepted or record['stderr']:
                raise ValueError('Ray original/adapted predicate disagrees with finite result classification')
        else:
            artifact = target / ('strict.wasm' + ('.raw.wasm' if system == 'raw' else ''))
            command = [tools['NODE'], '--disable-warning=ExperimentalWarning', driver.HERE / 'ray-host.mjs', artifact, specfile, '--validate']
            record = driver.execute(command, cwd, environment)
            driver.require_success(record)
            check_file_events(json.loads(record['stdout']), case)
        image = output_path(cwd, spec).read_bytes()
        images.append(image)
        records.append(dict(record, system=system, image_sha256=hashlib.sha256(image).hexdigest(), image_bytes=len(image)))
    if any(image != images[0] for image in images):
        raise ValueError('Ray complete small images differ between original, adapted, raw and optimized programs')
    (target / (case['label'] + '.pgm')).write_bytes(images[0])
    for cwd in (target, target / 'original', target / 'adapted'):
        output_path(cwd, spec).unlink()
    return dict(case=case, accepted=accepted, records=records)


def check_file_events(observation, case):
    count = max(0, case['count'])
    expected = []
    for index in range(count):
        if index or case['existing']:
            expected.append(['path_unlink_file', 0])
        expected.extend((['path_open', 0], ['fd_close', 0]))
    if observation['events'] != expected:
        raise ValueError('Ray open/delete/close order or complete iteration count changed')


def validate_images(directory, runner, tools, environment, driver):
    target = build_viewports(directory, runner, tools, environment, driver)
    records = []
    for case in image_cases():
        records.append(validate_image_case(target, case, runner, tools, environment, driver))
        driver.save(target / 'validation.json', records)
    # Only immutable reference files remain in the frozen inventory. Future
    # processes create their workload outputs outside that inventory.
    spec = driver.load(directory / 'spec.json')
    for cwd in (target, target / 'original', target / 'adapted'):
        output_path(cwd, spec).unlink(missing_ok=True)


# ---- Bit-exact geometry observations, including source-specific edge behavior ----

GEOMETRY_COMMON = '''(define (emit-point point)
  (emit-f64 (point-x point)) (emit-f64 (point-y point)) (emit-f64 (point-z point)))
(define (probe-root a b c)
  (let ((root (minroot a b c)))
    (emit-i64 (if (probe-root? root) 1 0))
    (when (probe-root? root) (emit-f64 (probe-root-value root)))))
(define (probe-candidate sphere origin ray)
  (let ((point (intersect sphere origin ray)))
    (emit-i64 (if (probe-candidate? point) 1 0))
    (when (probe-candidate? point) (emit-point (probe-candidate-point point)))))
(define (probe-hit origin ray)
  (let ((selected (first-hit origin ray)))
    (emit-i64 (if (probe-hit? selected) 1 0))
    (when (probe-hit? selected)
      (emit-f64 (sphere-color (probe-hit-sphere selected)))
      (emit-point (probe-hit-point selected)))))
(define (probe-extrema left right)
  (emit-f64 (probe-min left right)) (emit-f64 (probe-max left right)))
(define (geometry-probe ignored)
  (probe-root 1.0 0.0 1.0)
  (probe-root 1.0 -2.0 1.0)
  (probe-root 1.0 3.0 2.0)
  (probe-root 1.0 -3.0 0.0)
  (probe-root 0.0 2.0 -4.0)
  (probe-root 0.0 0.0 1.0)
  (probe-root 0.0 0.0 0.0)
  (probe-root 1.0 (probe-float 1) 0.0)
  (probe-extrema 0.0 (probe-float 0))
  (probe-extrema (probe-float 0) 0.0)
  (probe-extrema (probe-float 1) 1.0)
  (probe-extrema 1.0 (probe-float 1))
  (probe-extrema (probe-float 2) (probe-float 3))
  (let* ((origin (make-point 0.0 0.0 0.0)) (ray (make-point 0.0 0.0 -1.0))
         (behind (make-sphere 0.25 1.0 (make-point 0.0 0.0 10.0)))
         (tangent (make-sphere 0.5 1.0 (make-point 1.0 0.0 -10.0)))
         (first (make-sphere 0.5 1.0 (make-point 0.0 0.0 -10.0)))
         (second (make-sphere 0.75 1.0 (make-point 0.0 0.0 -10.0))))
    (probe-candidate behind origin ray) (probe-candidate tangent origin ray)
    (probe-candidate first origin (make-point 1.0 0.0 0.0))
    (probe-world! '()) (probe-hit origin ray)
    (probe-world! (cons behind '())) (probe-hit origin ray)
    (probe-world! (cons first (cons second '()))) (probe-hit origin ray)
    (probe-world! (cons second (cons first '()))) (probe-hit origin ray)
    (probe-world! (cons (make-sphere 0.5 1.0 (make-point 0.0 0.0 (probe-float 1))) '()))
    (probe-hit origin ray)
    (probe-world! (cons (make-sphere 0.5 0.0 (make-point 0.0 0.0 1e308)) '()))
    (probe-hit origin ray)
    (emit-point (normal first (make-point 0.0 0.0 -9.0)))
    (emit-f64 (lambert first (make-point 0.0 0.0 -9.0) ray)))
  (ray-test 0 "geometry-scene.pgm")
  (emit-i64 (length (probe-world)))
  (let loop ((spheres (probe-world)))
    (unless (null? spheres)
      (emit-f64 (sphere-color (car spheres)))
      (emit-f64 (sphere-radius (car spheres)))
      (emit-point (sphere-center (car spheres)))
      (loop (cdr spheres))))
  1)
'''
GEOMETRY_TYPED = '''(define probe-root? root?)
(define probe-root-value root-value)
(define probe-candidate? candidate?)
(define probe-candidate-point candidate-point)
(define probe-hit? hit?)
(define probe-hit-sphere hit-sphere)
(define probe-hit-point hit-point)
(define probe-min ray-min)
(define probe-max ray-max)
(define (probe-world! spheres) (ref-set! *world* spheres))
(define (probe-world) (ref-get *world*))
'''
GEOMETRY_ORIGINAL = '''(define (probe-root? value) (if value #t #f))
(define (probe-root-value value) value)
(define (probe-candidate? value) (if value #t #f))
(define (probe-candidate-point value) value)
(define (probe-hit? value) (if (vector-ref value 0) #t #f))
(define (probe-hit-sphere value) (vector-ref value 0))
(define (probe-hit-point value) (vector-ref value 1))
(define probe-min min)
(define probe-max max)
(define (probe-world! spheres) (set! *world* spheres))
(define (probe-world) *world*)
'''
GEOMETRY_CHEZ = '''(define (emit-i64 value) (display value) (newline))
(define (emit-f64 value)
  (if (nan? value) (display "NaN")
      (let ((bytes (make-bytevector 8)))
        (bytevector-ieee-double-native-set! bytes 0 value)
        (display (bytevector-u64-native-ref bytes 0))))
  (newline))
(define (probe-float index) (vector-ref (vector -0.0 +nan.0 +inf.0 -inf.0) index))
'''
GEOMETRY_STRICT = '''(define-extern emit-i64 "probe" "i64" (-> I64 Unit))
(define-extern emit-f64 "probe" "f64" (-> F64 Unit))
(define-extern probe-float "probe" "float" (-> I64 F64))
(: geometry-probe (-> I64 I64))
'''
GEOMETRY_HOST = '''import fs from 'node:fs';
import assert from 'node:assert/strict';
import {WASI} from 'node:wasi';
const module = new WebAssembly.Module(fs.readFileSync(process.argv[2]));
const wasi = new WASI({version:'preview1',args:[],env:{},preopens:{'.':process.cwd()},returnOnExit:true});
const values = [], bytes = new DataView(new ArrayBuffer(8));
const instance = new WebAssembly.Instance(module, {
  wasi_snapshot_preview1:wasi.wasiImport,
  benchmark:{input_i64:()=>1n,hide_i64:x=>x,barrier:()=>1,path_length:()=>0n,path_character:()=>32},
  probe:{i64:value=>values.push(value.toString()), float:index=>[-0,NaN,Infinity,-Infinity][Number(index)],
    f64:value=>{bytes.setFloat64(0,value,true);values.push(Number.isNaN(value)?'NaN':bytes.getBigUint64(0,true).toString());}}});
let failure;
try {wasi.initialize(instance);instance.exports.main();assert.equal(instance.exports['geometry-probe'](0n),1n);}
catch(error){failure=error;}
finally {try{assert.equal(instance.exports['close-resources'](),0);}catch(error){failure??=error;}}
if(failure)throw failure;
console.log(values.join('\\n'));
'''


def build_geometry(directory, runner, tools, environment, driver):
    target = directory / 'geometry-probes'
    target.mkdir()
    spec = dict(driver.load(directory / 'spec.json'), export='geometry-probe')
    driver.save(target / 'spec.json', spec)
    shutil.copyfile(directory / 'runtime.wasm', target / 'runtime.wasm')
    source = (directory / 'strict.scm').read_text() + GEOMETRY_STRICT + GEOMETRY_TYPED + GEOMETRY_COMMON
    (target / 'strict.scm').write_text(source)
    (target / 'host.mjs').write_text(GEOMETRY_HOST)
    driver.build_strict(target, tools, environment)
    for system in ('original', 'adapted'):
        control = target / system
        control.mkdir()
        origin = directory if system == 'original' else directory / 'same-source-chez'
        source = (origin / 'program.scm').read_text()
        source = replace(source, '\n(run-benchmark)\n', '\n')
        helpers = GEOMETRY_ORIGINAL if system == 'original' else GEOMETRY_TYPED
        (control / 'program.scm').write_text(source + GEOMETRY_CHEZ + helpers + GEOMETRY_COMMON + '(geometry-probe 0)\n')
        driver.build_chez(control, runner, environment, 'build.json')
    return target


def validate_geometry(directory, runner, tools, environment, driver):
    target = build_geometry(directory, runner, tools, environment, driver)
    observations, records = [], []
    for system in ('original', 'adapted', 'raw', 'optimized'):
        if system in ('original', 'adapted'):
            command = [tools['CHEZ'], '--program', target / system / 'program.so']
        else:
            artifact = target / ('strict.wasm' + ('.raw.wasm' if system == 'raw' else ''))
            command = [tools['NODE'], '--disable-warning=ExperimentalWarning', target / 'host.mjs', artifact]
        record = driver.execute(command, target, environment)
        records.append(dict(record, system=system))
        driver.save(target / 'validation.json', records)
        driver.require_success(record)
        observations.append(record['stdout'].splitlines())
    if any(values != observations[0] for values in observations):
        raise ValueError('Ray floating bit patterns, option presence, or ordered tie selection differ')
    if observations[0][-166:] != scene_oracle():
        raise ValueError('Ray scene differs from all 33 original spheres in reverse construction order')
    (target / 'geometry-scene.pgm').unlink()


def check_formatter_source(driver):
    library = (driver.ROOT / 'src/snail/io.sld').read_text()
    check_write_string_source(library)
    for name in ('write-i64', 'write-negative-digits'):
        actual = form(library, '(define (' + name + ' ')
        control = form(CHEZ_FORMAT, '(define (' + name + ' ')
        if re.sub(r'\s+', '', actual) != re.sub(r'\s+', '', control):
            raise ValueError('adapted Chez must use the strict Scheme formatting bodies')


def check_write_string_source(library):
    prefix = '(define (write-string-to '
    actual, control = form(library, prefix), form(CHEZ_WRITE_STRING, prefix)
    if re.sub(r'\s+', '', actual) != re.sub(r'\s+', '', control):
        raise ValueError('adapted Chez must use the strict Scheme write-string-to body')
    overload = '(define-overload write-string (-> String OutputPort Unit) write-string-to)'
    if form(library, '(define-overload write-string (-> String OutputPort ') != overload:
        raise ValueError('two-argument write-string must select the checked write-string-to body')


def scene_oracle():
    spheres = [(0.8, 200.0, 0.0, -300.0, -1200.0), (0.7, 200.0, -80.0, -150.0, -1200.0),
               (0.9, 200.0, 70.0, -100.0, -1200.0)]
    spheres += [(0.75, 40.0, x * 200.0, 300.0, z * -400.0) for x in range(-2, 3) for z in range(2, 8)]
    return ['33'] + [str(struct.unpack('<Q', struct.pack('<d', value))[0])
                     for sphere in reversed(spheres) for value in sphere]
