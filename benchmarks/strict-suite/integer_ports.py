#!/usr/bin/env python3
"""Prepare the complete pi/Chudnovsky algorithms with strict exact Integer values."""

import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time

from data_ports import form

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
CORPUS = ROOT / 'benchmarks/r7rs-benchmarks'
REVISION = '85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1'


# ---- Counted source edits preserve every numerical algorithm ----


def edit(source, before, after, edits, count=1):
    if source.count(before) != count:
        raise ValueError(f'expected {count} occurrences of {before!r}')
    edits.append(dict(before=before, after=after, count=count,
                      offsets=[match.start() for match in re.finditer(re.escape(before), source)]))
    return source.replace(before, after)


def integer_literals(source):
    tokens = r';[^\n]*|"(?:[^"\\]|\\.)*"|[^\s()]+|[()]'
    return re.sub(tokens, lambda m: '(integer-from-i64 ' + m[0] + ')'
                  if re.fullmatch(r'[+-]?\d+', m[0]) else m[0], source)


def adaptation(name, source):
    edits = []
    if name == 'pi':
        before = form(source, '(define (square-root ')
        source = edit(source, before, '(define (square-root x) (integer-sqrt x))', edits)
        names = ['pi-brent-salamin', 'pi-borwein2', 'pi-borwein4']
    else:
        before = form(source, '(define (integer-sqrt ')
        source = edit(source, before, '', edits)
        source = edit(source, '(exact (floor (+ 2 (/ digits 14.181647462))))', '(term-count digits)', edits)
        for before, after in [
            ('(* (- (* 6 b) 5) (- (* 2 b) 1) (- (* 6 b) 1))',
             '(* (* (- (* 6 b) 5) (- (* 2 b) 1)) (- (* 6 b) 1))'),
            ('(* (expt -1 b) g (+ (* b ch-B) ch-A))',
             '(* (* (expt -1 b) g) (+ (* b ch-B) ch-A))'),
            ('(* p ch-C sqrt-C)', '(* (* p ch-C) sqrt-C)')]:
            source = edit(source, before, after, edits)
        for variable in ['ch-A', 'ch-B', 'ch-C', 'ch-C^3', 'ch-D']:
            before = form(source, '(define ' + variable + ' ')
            source = edit(source, before, integer_literals(before), edits)
        names = ['ch-split', 'pi']
    for definition in names:
        before = form(source, '(define (' + definition + ' ')
        source = edit(source, before, integer_literals(before), edits)
    return source, edits


def restore(source, edits):
    for change in reversed(edits):
        difference = len(change['after']) - len(change['before'])
        for index, offset in reversed(list(enumerate(change['offsets']))):
            offset += index * difference
            end = offset + len(change['after'])
            if source[offset:end] != change['after']:
                raise ValueError('source edit cannot be reversed')
            source = source[:offset] + change['before'] + source[end:]
    return source


def kernel(source):
    imports = form(source, '(import ')
    return source[:source.index('(define (run-benchmark)')].replace(imports, '')


def rewrite_integer_operators(name, source):
    names = ['pi-brent-salamin','pi-borwein2','pi-borwein4'] if name == 'pi' else ['ch-split','pi']
    mapping = {'+':'integer-add','-':'integer-subtract','*':'integer-multiply',
               '=':'integer=?','<':'integer<?','quotient':'integer-quotient'}
    for definition in names:
        before = form(source, '(define (' + definition + ' ')
        after = re.sub(r'\((\+|-|\*|=|<|quotient)(?=\s)', lambda m:'('+mapping[m[1]], before)
        source = source.replace(before,after)
    if name == 'pi':
        source = source.replace('(- bs b2)', '(integer-subtract bs b2)').replace('(- b4 b2)', '(integer-subtract b4 b2)')
    return source


# ---- Runtime scalar inputs and typed complete-result predicates ----

STRICT_HELPERS = '''(define-overload expt (-> Integer I64 Integer) integer-power)
(define-overload expt (-> Integer Integer Integer) integer-expt)
(define (square value) (* value value))
(define (list . values) values)
(define (cadr values) (car (cdr values)))
(define (caddr values) (car (cdr (cdr values))))
(define (floor-real value)
  (let ((whole (truncate value))) (if (< value whole) (- whole 1.0) whole)))
(define (term-count digits)
  (integer-from-i64 (f64->i64 (floor-real (+ 2.0 (/ (i64->f64 digits) 14.181647462))))))
'''
STRICT_INPUTS = '''(define-extern input-i64 "benchmark" "input_i64" (-> I32 I64))
(define-extern expected-count "benchmark" "expected_count" (-> I64))
(define-extern expected-length "benchmark" "expected_length" (-> I64 I64))
(define-extern expected-character "benchmark" "expected_character" (-> I64 I64 Char))
(define-extern hide-i64 "benchmark" "hide_i64" (-> I64 I64))
(define-extern emit-character "benchmark" "emit_character" (-> Char Unit))
(define (expected-integer index)
  (let* ((count (expected-length index)) (text (make-string count)))
    (let loop ((at 0))
      (if (= at count) (integer-from-string text)
          (begin (string-set! text at (expected-character index at)) (loop (+ at 1)))))))
(define (same-integers? left right)
  (if (null? left) (null? right)
      (and (not (null? right)) (= (car left) (car right))
           (same-integers? (cdr left) (cdr right)))))
(define (same-rows? left right)
  (if (null? left) (null? right)
      (and (not (null? right)) (same-integers? (car left) (car right))
           (same-rows? (cdr left) (cdr right)))))
(define (write-integer value)
  (let ((text (integer->string value)))
    (let loop ((at 0))
      (unless (= at (string-length text))
        (emit-character (string-ref text at)) (loop (+ at 1))))))
(define (write-list render values)
  (emit-character (integer->char 40))
  (let loop ((tail values) (first? #t))
    (unless (null? tail)
      (unless first? (emit-character #\\space))
      (render (car tail)) (loop (cdr tail) #f)))
  (emit-character (integer->char 41)))
(define (write-row row) (write-list write-integer row))
(define input0 (input-i64 (ann 0 I32)))
(define input1 (input-i64 (ann 1 I32)))
(define input2 (input-i64 (ann 2 I32)))
'''


def strict_source(name, adapted):
    row = name == 'pi'
    element = '(List Integer)' if row else 'Integer'
    expected = ('(list (expected-integer at) (expected-integer (+ at 1)) '
                '(expected-integer (+ at 2)))') if row else '(expected-integer at)'
    width = 3 if row else 1
    tail = f'''(: expected (List {element}))
(define expected
  (let loop ((at 0))
    (if (= at (expected-count)) '() (cons {expected} (loop (+ at {width}))))))
(define saved (ref (ann '() (List {element}))))
(: bench (-> I64 I64))
(define (bench count)
  (if (< count 1) 0
      (let loop ((index 0) (result (ann '() (List {element}))))
        (if (< index count)
            (loop (+ index 1) (pies (hide-i64 input0) (hide-i64 input1) (hide-i64 input2)))
            (begin (ref-set! saved result)
                   (if ({'same-rows?' if row else 'same-integers?'} result expected) 1 0))))))
(: observe (-> Unit))
(define (observe)
  (write-list {'write-row' if row else 'write-integer'} (ref-get saved))
  (emit-character #\\newline))
(unit)
'''
    return '(import (snail strict) (snail integer))\n' + STRICT_HELPERS + kernel(adapted) + STRICT_INPUTS + tail


# ---- Chez controls: original arithmetic and the identical limb body ----

CHEZ_HARNESS = '''(define (run-r7rs-benchmark name count thunk correct?)
  (let loop ((index 0) (result #f))
    (if (< index count) (loop (+ index 1) (thunk))
        (begin (unless (correct? result) (error 'benchmark "complete result differs" result))
               (write result) (newline)))))
(run-benchmark)
'''
CHEZ_ADAPTER = '''(define (integer-from-i64 value) value)
(define (integer-sqrt value) (let-values (((root remainder) (exact-integer-sqrt value))) root))
(define (term-count digits) (exact (floor (+ 2 (/ digits 14.181647462)))))
'''
CHEZ_SCALARS = '''(define-syntax : (syntax-rules () ((_ . rest) (begin))))
(define-syntax ann (syntax-rules () ((_ value type) value)))
(define-syntax define-overload (syntax-rules () ((_ . rest) (begin))))
(define (unit) (void))
(define (unreachable) (error 'integer "invalid exact-integer operation"))
(define (checked-i64 value)
  (if (<= -9223372036854775808 value 9223372036854775807) value (error 'i64 "overflow" value)))
(define (checked-add a b) (checked-i64 (+ a b)))
(define (checked-subtract a b) (checked-i64 (- a b)))
(define (checked-multiply a b) (checked-i64 (* a b)))
(define (checked-quotient a b) (checked-i64 (quotient a b)))
(define (checked-remainder a b) (checked-i64 (remainder a b)))
(define (i64->i32 value)
  (if (<= -2147483648 value 2147483647) value (error 'i32 "overflow" value)))
(define i32->i64 i64->i32)
(define (empty-vector) (vector))
(define (limb-copy! target at source start end)
  (do ((index start (+ index 1))) ((= index end))
    (vector-set! target (+ at (- index start)) (vector-ref source index))))
'''
CHEZ_RECORDS = {
    'Integer': '(define-record-type (Integer integer integer-value?) (fields (immutable negative integer-negative?) (immutable limbs integer-limbs)))',
    'IntegerDivision': '(define-record-type (IntegerDivision division division?) (fields (immutable quotient division-quotient) (immutable remainder division-remainder)))',
    'IntegerRoot': '(define-record-type (IntegerRoot root root?) (fields (immutable value root-value) (immutable remainder root-remainder)))',
}


def chez_limb_body():
    library = (ROOT/'src/snail/integer.sld').read_text()
    body = form(library,'(begin\n\n    ;; ---- Canonical')
    for name,replacement in CHEZ_RECORDS.items():
        original = form(body,'(define-data '+name+'\n')
        body = body.replace(original,replacement)
    mapping = {'+':'checked-add','-':'checked-subtract','*':'checked-multiply',
               'quotient':'checked-quotient','remainder':'checked-remainder','vector-copy!':'limb-copy!'}
    body = re.sub(r'\((\+|-|\*|quotient|remainder|vector-copy!)(?=\s)',lambda m:'('+mapping[m[1]],body)
    return CHEZ_SCALARS + body


def chez_source(name, original, adapted, mode):
    source = original if mode == 'original' else adapted
    source = source.replace(form(source,'(import '),'')
    hide = form((CORPUS/'src/common.scm').read_text(),'(define (hide ')
    if mode != 'limbs':
        helpers = '(define (square x) (* x x))\n' + (CHEZ_ADAPTER if mode == 'adapted' else '')
        return '(import (chezscheme))\n'+helpers+source+hide+'\n'+CHEZ_HARNESS
    body = rewrite_integer_operators(name,kernel(adapted))
    helpers = '''(define (square value) (integer-multiply value value))
(define (expt base exponent)
  (if (integer-value? exponent) (integer-expt base exponent) (integer-power base exponent)))
(define (term-count digits) (integer-from-i64 (exact (floor (+ 2 (/ digits 14.181647462))))))
'''
    read_result = ('(map (lambda (row) (map integer->string row)) result)' if name=='pi'
                   else '(map integer->string result)')
    expected_result = ('(map (lambda (row) (map number->string row)) expected)' if name=='pi'
                       else '(map number->string expected)')
    render = ('(map (lambda (row) (map string->number row)) strings)' if name=='pi'
              else '(map string->number strings)')
    driver=f'''(define count (read)) (define first (read)) (define last (read)) (define step (read))
(define expected (read))
(let loop ((index 0) (result #f))
  (if (< index count) (loop (+ index 1) (pies (hide count first) (hide count last) (hide count step)))
      (let ((strings {read_result}))
        (unless (equal? strings {expected_result}) (error 'benchmark "limb result differs"))
        (write {render}) (newline))))
'''
    return '(import (chezscheme))\n'+chez_limb_body()+helpers+body+hide+'\n'+driver


# ---- Exact input tables and complete scalar output ----


def read_input(text):
    tokens=iter(re.findall(r'[()]|[+-]?\d+',text))
    def read(token):
        if token != '(': return int(token)
        values=[]
        for token in tokens:
            if token==')': return values
            values.append(read(token))
        raise ValueError('incomplete input')
    return [read(token) for token in tokens]


def scheme(value):
    return '('+' '.join(map(scheme,value))+')' if isinstance(value,list) else str(value)


def specification(name,text):
    count,first,last,step,expected=read_input(text)
    flattened=[item for row in expected for item in row] if name=='pi' else expected
    return dict(name=name,count=count,inputs=[first,last,step],expected=[str(value) for value in flattened],
                output=scheme(expected)+'\n',diagnostic_only=True)


# ---- Bounded preparation processes retain all failures ----


def save(path,value):
    path.write_text(json.dumps(value,indent=2)+'\n')


def executing_group(group):
    members = []
    for path in Path('/proc').glob('[0-9]*/stat'):
        try:
            fields = path.read_text().rsplit(')', 1)[1].split()
            if int(fields[2]) == group and fields[0] not in ('Z', 'X'):
                members.append(int(path.parent.name))
        except (OSError, ValueError, IndexError):
            pass
    return members


def finish_group(group):
    deadline = time.monotonic() + 5
    while True:
        try:
            os.killpg(group, signal.SIGKILL)
        except ProcessLookupError:
            pass
        members = executing_group(group)
        if not members or time.monotonic() >= deadline:
            return members
        time.sleep(0.02)


def execute(command,directory,path,environment,stdin=None):
    command=list(map(str,command))
    child=subprocess.Popen(command,cwd=directory,env=environment,text=True,stdin=subprocess.PIPE,
                           stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
    expired=False
    try:
        stdout,stderr=child.communicate(stdin,timeout=1800)
    except subprocess.TimeoutExpired:
        expired=True;os.killpg(child.pid,signal.SIGKILL);stdout,stderr=child.communicate(timeout=10)
    finally:
        remaining = finish_group(child.pid)
    record=dict(command=command,returncode=child.returncode,stdout=stdout,stderr=stderr,
                timeout=expired,process_group=child.pid,diagnostic_only=True,executing_descendants=remaining)
    save(path,record)
    if expired or remaining or child.returncode: raise RuntimeError('preparation failed: '+str(path))
    return stdout


def prepare(name,output,environment):
    directory=output/name;directory.mkdir(parents=True,exist_ok=True)
    original=(CORPUS/'src'/f'{name}.scm').read_text();data=(CORPUS/'inputs'/f'{name}.input').read_text()
    adapted,edits=adaptation(name,original)
    if restore(adapted,edits) != original: raise ValueError('source restoration differs')
    (directory/'original.scm').write_text(original);(directory/'adapted.scm').write_text(adapted)
    (directory/'input').write_text(data);save(directory/'edits.json',edits)
    (directory/'adaptation.diff').write_text(''.join(difflib.unified_diff(original.splitlines(True),adapted.splitlines(True),fromfile='original.scm',tofile='adapted.scm')))
    spec=specification(name,data);save(directory/'spec.json',spec)
    for mode in ['original','adapted','limbs']:
        source=directory/f'chez-{mode}.sps';source.write_text(chez_source(name,original,adapted,mode))
        actual=execute([environment.get('CHEZ','scheme'),'--script',source],directory,directory/f'chez-{mode}.json',environment,data)
        (directory/f'chez-{mode}.output').write_text(actual)
        if actual != spec['output']: raise ValueError(f'{name}: Chez {mode} entire output differs')
    strict=directory/'strict.scm';strict.write_text(strict_source(name,adapted));wasm=directory/'strict.wasm'
    execute([ROOT/'scripts/build-strict','--export','bench','--export','observe',strict,wasm],ROOT,directory/'strict-build.json',environment)
    for kind,module in [('raw',Path(str(wasm)+'.raw.wasm')),('optimized',wasm)]:
        actual=execute([environment.get('NODE','node'),HERE/'integer-host.mjs',module,directory/'spec.json'],directory,directory/f'{kind}.json',environment)
        (directory/f'{kind}.output').write_text(actual)
        if actual != spec['output']: raise ValueError(f'{name}: {kind} entire output differs')
    native_input=directory/'native-input.txt'
    native_input.write_text(' '.join(map(str,[spec['count'],*spec['inputs'],len(spec['expected'])]))+'\n'+'\n'.join(spec['expected'])+'\n')
    native=directory/'native'
    execute([ROOT/'scripts/build-native','--wasm','--c-provider','benchmark',HERE/'integer-provider.h',
             HERE/'integer-provider.c','--entry-c',HERE/'integer-entry.c',wasm,native],ROOT,directory/'native-build.json',environment)
    actual=execute([native,native_input],directory,directory/'native.json',environment)
    (directory/'native.output').write_text(actual)
    if actual != spec['output']: raise ValueError(f'{name}: native entire output differs')
    save(directory/'summary.json',dict(passed=True,count=spec['count'],inputs=spec['inputs'],diagnostic_only=True,
         original_sha256=hashlib.sha256(original.encode()).hexdigest(),input_sha256=hashlib.sha256(data.encode()).hexdigest(),
         output_sha256=hashlib.sha256(actual.encode()).hexdigest(),corpus_revision=REVISION))
    print(f'PASS {name}: full count {spec["count"]}, complete output on three Chez controls, raw/optimized Wasm, native64',flush=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'build/strict-integer-ports')
    parser.add_argument('names', nargs='*', default=['pi','chudnovsky'])
    options=parser.parse_args()
    if len(set(options.names)) != len(options.names) or set(options.names) - {'pi','chudnovsky'}:
        parser.error('choose distinct pi and/or chudnovsky workloads')
    output=options.output.resolve();output.mkdir(parents=True,exist_ok=True)
    environment={**os.environ,'BINARYEN_CORES':'1'}
    revision = execute(['git', '-C', CORPUS, 'rev-parse', 'HEAD'], ROOT,
                       output/'corpus-revision.json', environment).strip()
    changes = execute(['git', '-C', CORPUS, 'status', '--porcelain', '--untracked-files=no'], ROOT,
                      output/'corpus-status.json', environment)
    if revision != REVISION or changes:
        raise ValueError('benchmark corpus must be clean at ' + REVISION)
    for name in options.names: prepare(name,output,environment)


if __name__=='__main__': main()
