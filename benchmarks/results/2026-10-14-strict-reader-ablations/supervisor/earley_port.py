"""Preserve Feeley's complete Earley parser with concrete storage roles."""

import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import time

from data_ports import form, replace
from string_port import exact_json_integer, i64


# ---- Concrete records and the finite workload vocabulary ----

# These are atom identities, not a general implementation of Scheme symbols.
# s/a are canonical; x/y/e/v/+/= exercise the source's documented grammar.
SYMBOLS = ('s', 'a', 'x', 'y', 'e', 'v', 'plus', 'equals', 'unknown')
SYMBOL_TEXT = ('s', 'a', 'x', 'y', 'e', 'v', '+', '=', 'unknown')
PRODUCTS = (
    ('Definition', 'definition', (('head', 'EarleySymbol'), ('rules', '(List (List EarleySymbol))'))),
    ('(Token T)', 'token', (('info', 'EarleySymbol'), ('classes', '(List T)'))),
    ('RuleName', 'rule-name', (('symbol', 'EarleySymbol'), ('number', 'I64'))),
    ('Configuration', 'configuration', (('slots', '(Vector (Optional I64))'),)),
    ('State', 'state', (('head', '(Ref I64)'), ('sets', '(Vector (Optional Configuration))'))),
    ('ParserDescription', 'parser-description', (
        ('lexer', '(-> (List EarleySymbol) (List (Token EarleySymbol)))'),
        ('nts', '(Vector EarleySymbol)'), ('starters', '(Vector (List I64))'),
        ('enders', '(Vector (List I64))'), ('predictors', '(Vector (List I64))'),
        ('steps', '(Vector I64)'), ('names', '(Vector (Optional RuleName))'))),
    ('Parse', 'parse-record', (
        ('nts', '(Vector EarleySymbol)'), ('starters', '(Vector (List I64))'),
        ('enders', '(Vector (List I64))'), ('predictors', '(Vector (List I64))'),
        ('steps', '(Vector I64)'), ('names', '(Vector (Optional RuleName))'),
        ('toks', '(Vector (Token I64))'), ('states', '(Vector (Optional State))'),
        ('parsed', '(-> EarleySymbol I64 I64 (Vector EarleySymbol) (Vector (List I64)) (Vector (Optional State)) Bool)'),
        ('trees', '(-> EarleySymbol I64 I64 (Vector EarleySymbol) (Vector (List I64)) (Vector I64) (Vector (Optional RuleName)) (Vector (Token I64)) (Vector (Optional State)) (Optional (List (List TreePart))))'),
        ('count', '(-> EarleySymbol I64 I64 (Vector EarleySymbol) (Vector (List I64)) (Vector I64) (Vector (Token I64)) (Vector (Optional State)) (Optional I64))'))),
)


def strict_products():
    return ''.join('(define-data ' + typename + '\n  (' + constructor + '\n    '
                   + '\n    '.join(f'({name} {kind} {constructor}-{name})' for name, kind in fields)
                   + '))\n' for typename, constructor, fields in PRODUCTS)


def chez_products():
    result = ''
    for _, constructor, fields in PRODUCTS:
        names = ' '.join(name for name, _ in fields)
        result += f'(define ({constructor} {names}) (vector {names}))\n'
        result += ''.join(f'(define ({constructor}-{name} value) (vector-ref value {index}))\n'
                          for index, (name, _) in enumerate(fields))
    return result


STRICT_TYPES = '''(define-data (Optional T) (absent) (present (value T optional-value)))
(: present? (All (T) (-> (Optional T) Bool)))
(define (present? value) (match value ((absent) #f) ((present item) #t)))
(define-data TreePart
  (name-part (value RuleName part-name))
  (token-part (value EarleySymbol part-token))
  (child-part (value (List TreePart) part-child)))
(define (part-kind value)
  (match value ((name-part name) 0) ((token-part token) 1) ((child-part child) 2)))
''' + '(define-data EarleySymbol ' + ' '.join('(' + name + '-symbol)' for name in SYMBOLS) + ')\n' + '''(define (symbol-code value)
  (match value ''' + ' '.join(f'(({name}-symbol) {index})' for index, name in enumerate(SYMBOLS)) + '))\n' + strict_products()
CHEZ_TYPES = '''(define-syntax : (syntax-rules () ((_ . signature) (begin))))
(define-syntax ann (syntax-rules () ((_ value type) value)))
(define (absent) #f)
(define (present value) (vector value))
(define (present? value) (if value #t #f))
(define (optional-value value) (vector-ref value 0))
(define (name-part value) (vector 0 value))
(define (token-part value) (vector 1 value))
(define (child-part value) (vector 2 value))
(define (part-kind value) (vector-ref value 0))
(define (part-name value) (vector-ref value 1))
(define (part-token value) (vector-ref value 1))
(define (part-child value) (vector-ref value 1))
(define (ref value) (vector value))
(define (ref-get value) (vector-ref value 0))
(define (ref-set! cell value) (vector-set! cell 0 value))
(define ref-eq? eq?)
(define vector-eq? eq?)
(define (unit) (if #f #f))
(define (unreachable) (error 'earley "invalid typed boundary"))
''' + ''.join(f"(define ({name}-symbol) '{atom})\n" for name, atom in zip(SYMBOLS, SYMBOL_TEXT)) + '''(define (symbol-code value)
  (let loop ((symbols '(s a x y e v + = unknown)) (index 0))
    (if (eq? value (car symbols)) index (loop (cdr symbols) (+ index 1)))))
''' + chez_products()
COMMON = ''';; Source #f is distinct from every index, including -1 and zero.
;; Configuration slots retain the original five-slot header and intrusive links:
;; 0 work-list link, 1/2 old tail/head, 3/4 new tail/head, 5+i origin link.
(define (configuration-ref value index) (vector-ref (configuration-slots value) index))
(define (configuration-number value index) (optional-value (configuration-ref value index)))
(define (configuration-set! value index number)
  (vector-set! (configuration-slots value) index (present number)))
(define (state-ref value conf) (vector-ref (state-sets value) conf))
(define (state-set! value conf set) (vector-set! (state-sets value) conf (present set)))
(define (state-at states index) (optional-value (vector-ref states index)))
(define (state-work value) (ref-get (state-head value)))
(define (state-work! value head) (ref-set! (state-head value) head))
(define (same-symbol? first second) (= (symbol-code first) (symbol-code second)))
(define (symbol-member? value values)
  (and (not (null? values))
       (or (same-symbol? value (car values)) (symbol-member? value (cdr values)))))
(: earley-list (All (T) (-> (Rest T) (List T))))
(define (earley-list . values) values)
(: earley-append (All (T) (-> (List T) (List T) (List T))))
(define (earley-append first last)
  ;; The final prefix has millions of trees. Explicit reversal bounds stack
  ;; use, adding one temporary list spine; the final suffix remains shared.
  (let loop ((reversed (earley-reverse first)) (result last))
    (if (null? reversed) result
        (loop (cdr reversed) (cons (car reversed) result)))))
(: earley-reverse (All (T) (-> (List T) (List T))))
(define (earley-reverse values)
  (let loop ((values values) (result '()))
    (if (null? values) result (loop (cdr values) (cons (car values) result)))))
(: earley-map (All (A B) (-> (-> A B) (List A) (List B))))
(define (earley-map procedure values)
  (if (null? values) '()
      (let ((head (procedure (car values))))
        (cons head (earley-map procedure (cdr values))))))
;; This literal precedes the workload, just like the source quoted grammar.
(define canonical-grammar
  (earley-list (definition (s-symbol)
    (earley-list (earley-list (a-symbol)) (earley-list (s-symbol) (s-symbol))))))
'''
CONTRACTS = '''(: make-parser (-> (List Definition)
  (-> (List EarleySymbol) (List (Token EarleySymbol))) (-> (List EarleySymbol) Parse)))
(: parse->parsed? (-> Parse EarleySymbol I64 I64 Bool))
(: parse->trees (-> Parse EarleySymbol I64 I64 (Optional (List (List TreePart)))))
(: parse->nb-trees (-> Parse EarleySymbol I64 I64 (Optional I64)))
(: test (-> (List EarleySymbol) I64))
'''


# ---- Counted reversible substitutions leave every original parser loop ----


def adaptation(source):
    original, edits = source, []

    def edit(before, after, count=1):
        nonlocal source
        source = replace(source, before, after, count)
        edits.append(dict(before=before, after=after, count=count))

    # Definitions and lexical tokens have different concrete list-like roles.
    edit('(car def)', '(definition-head def)', 2)
    edit('(cdr def)', '(definition-rules def)', 3)
    edit('(member nt nts)', '(symbol-member? nt nts)')
    edit('(equal? (vector-ref nts i) nt)', '(same-symbol? (vector-ref nts i) nt)', 2)
    edit('(if (same-symbol? (vector-ref nts i) nt) i (loop (- i 1)))\n          #f)',
         '(if (same-symbol? (vector-ref nts i) nt) (present i) (loop (- i 1)))\n          (absent))')
    edit('(if (same-symbol? (vector-ref nts i) nt) i (loop (- i 1)))\n                #f)',
         '(if (same-symbol? (vector-ref nts i) nt) (present i) (loop (- i 1)))\n                (absent))')
    edit('(steps (make-vector nb-confs #f))', '(steps (make-vector nb-confs 0))')
    edit('(names (make-vector nb-confs #f))', '(names (make-vector nb-confs (absent)))')
    edit('(list (vector-ref nts i) 0)', '(present (rule-name (vector-ref nts i) 0))')
    edit('(list head rule-num)', '(present (rule-name head rule-num))')
    edit('(let ((i (ind nt nts)))', '(let ((i (optional-value (ind nt nts))))')
    edit('(vector-set! steps conf (ind nt nts))', '(vector-set! steps conf (optional-value (ind nt nts)))')
    edit('(- (ind head nts) nb-nts)', '(- (optional-value (ind head nts)) nb-nts)')
    edit('(cdr tok)', '(token-classes tok)')
    edit('(car tok)', '(token-info tok)')
    edit('(if i\n', '(if (present? i)\n')
    edit('(loop (cdr l1) (cons i l2))', '(loop (cdr l1) (cons (optional-value i) l2))')
    edit('(cons (token-info tok) (reverse l2))', '(token (token-info tok) (reverse l2))')
    edit('(cdr (vector-ref toks i))', '(token-classes (vector-ref toks i))')
    edit('(car (vector-ref toks i))', '(token-info (vector-ref toks i))')
    # State vectors keep their initialization loop; configuration slots keep
    # their source offsets. Only the heterogeneous outer head becomes a Ref.
    edit('(make-vector (+ nb-toks 1) #f)', '(make-vector (+ nb-toks 1) (absent))')
    edit('(make-vector (+ nb-confs 1) #f)', '(state (ref -1) (make-vector nb-confs (absent)))')
    edit('(vector-set! v 0 -1)', '(state-work! v -1)')
    edit('(vector-set! states i v)', '(vector-set! states i (present v))')
    edit('(make-vector (+ state-num 6) #f)', '(configuration (make-vector (+ state-num 6) (absent)))')
    for name, count in (('state', 3), ('state*', 1)):
        edit(f'(vector-ref {name} (+ conf 1))', f'(state-ref {name} conf)', count)
    edit('(vector-set! state (+ conf 1) conf-set)', '(state-set! state conf conf-set)')
    for name, count in (('states', 3), ('states*', 2)):
        edit(f'(vector-ref {name} state-num)', f'(state-at {name} state-num)', count)
    for index, count in (('i', 1), ('j', 6), ('k', 2)):
        edit(f'(vector-ref states {index})', f'(state-at states {index})', count)
    for name, count in (('state', 2), ('state*', 1)):
        edit(f'(vector-ref {name} 0)', f'(state-work {name})', count)
    edit('(vector-set! state 0 ', '(state-work! state ', 2)
    edit('(vector-set! state* 0 ', '(state-work! state* ')
    edit('(vector-ref conf-set ', '(configuration-number conf-set ', 10)
    edit('(vector-set! conf-set', '(configuration-set! conf-set', 12)
    # Reads used as membership tests retain Optional; traversed links unwrap.
    edit('(configuration-number conf-set (+ i 5))', '(configuration-ref conf-set (+ i 5))')
    edit('(if conf-set\n                conf-set', '(if (present? conf-set)\n                (optional-value conf-set)')
    edit('(if conf-set\n                (conf-set-next conf-set i)\n                #f)',
         '(if (present? conf-set)\n                (conf-set-next (optional-value conf-set) i)\n                (absent))')
    edit('(not (conf-set-next conf-set i))', '(not (present? (conf-set-next conf-set i)))', 2)
    edit('(unless (conf-set-next conf-set* i)', '(unless (present? (conf-set-next conf-set* i))')
    edit('(not (conf-set-next starter-set state-num))',
         '(not (present? (conf-set-next starter-set state-num)))')
    edit('(conf-set-next other-set i)', '(optional-value (conf-set-next other-set i))', 2)
    # All member? uses are conditional; the function's returned optional is
    # unchanged and preserves the distinction between a missing origin and -1.
    edit('(if (conf-set-member? state conf i)', '(if (present? (conf-set-member? state conf i))')
    edit('(conf-set-member? state ender state-num)', '(present? (conf-set-member? state ender state-num))')
    edit('(conf-set-member? (state-at states j) conf i)',
         '(present? (conf-set-member? (state-at states j) conf i))', 3)
    for before in set(re.findall(r'\(conf-set-member\? \(state-at states k\)\s+prev i\)', source)):
        edit(before, '(present? ' + before + ')', source.count(before))
    # Unwrap successful optional-set lookups at their original bindings.
    edit('(let* ((step (vector-ref steps conf))\n                         (conf-set (state-ref state conf))',
         '(let* ((step (vector-ref steps conf))\n                         (conf-set (optional-value (state-ref state conf)))')
    edit('(let* ((conf-set (state-ref state* conf))', '(let* ((conf-set (optional-value (state-ref state* conf)))')
    edit('(when pred-set\n', '(when (present? pred-set)\n')
    edit('(conf-set-union state next-set next pred-set)', '(conf-set-union state next-set next (optional-value pred-set))')
    edit('(if ender-set\n', '(if (present? ender-set)\n', 3)
    edit('(conf-set-head ender-set)', '(conf-set-head (optional-value ender-set))', 3)
    edit('(conf-set-next ender-set k)', '(optional-value (conf-set-next (optional-value ender-set) k))', 5)
    edit('(loop2 (conf-set-next conf-set i))', '(loop2 (optional-value (conf-set-next conf-set i)))', 2)
    edit('(if nt*\n', '(if (present? nt*)\n', 3)
    edit('(vector-ref enders nt*)', '(vector-ref enders (optional-value nt*))', 3)
    # Ordered heterogeneous tree elements become a closed recursive variant.
    edit('(if name;;', '(if (present? name);;')
    edit('(list (list name (token-info (vector-ref toks i))))',
         '(list (list (name-part (optional-value name)) (token-part (token-info (vector-ref toks i)))))')
    edit('(list (list name))', '(list (list (name-part (optional-value name))))')
    edit('(list (car l3))', '(list (child-part (car l3)))')
    edit('                        trees)))\n                #f)))',
         '                        (present trees))))\n                (absent))))')
    edit('                        nb-trees)))\n                #f)))',
         '                        (present nb-trees))))\n                (absent))))')
    # Parser and parse products retain their stored callable fields.
    edit('(vector lexer\n', '(parser-description lexer\n')
    for index, (name, _) in enumerate(PRODUCTS[-2][2]):
        edit(f'(vector-ref parser-descr {index})', f'(parser-description-{name} parser-descr)')
    edit('(vector nts\n', '(parse-record nts\n')
    for index, (name, _) in enumerate(PRODUCTS[-1][2]):
        old = f'(vector-ref parse {index})'
        if old in source:
            edit(old, f'(parse-record-{name} parse)', source.count(old))
    edit("'( (s (a) (s s)) )", 'canonical-grammar')
    edit('(list x x)', '(token x (list x))')
    edit("(length (parse->trees x 's 0 n))", '(length (optional-value (parse->trees x (s-symbol) 0 n)))')
    for name in ('list', 'append', 'map', 'reverse'):
        for before in sorted(set(re.findall(r'\(' + name + r'\s', source))):
            edit(before, '(earley-' + name + before[-1], source.count(before))
    edit('(pair? ', '(not-null? ', source.count('(pair? '))
    restored = source
    for step in reversed(edits):
        restored = replace(restored, step['after'], step['before'], step['count'])
    if restored != original:
        raise ValueError('Earley edits did not restore the complete original kernel')
    return CONTRACTS + '(define (not-null? value) (not (null? value)))\n' + source, edits


def kernel(source):
    return adaptation(source)[0]


# ---- Runtime inputs and the full original equality predicate ----

# expected-kind distinguishes exact I64, #f and all other reader datums. The
# original timed loop starts at #f; its integer result is exact, never inexact.
INPUTS = '''(define input0 (native-input-i64 (ann 0 I32)))
(define expected-kind (native-input-i64 (ann 1 I32)))
(define expected-value (native-input-i64 (ann 2 I32)))
(define (hide-input count value) (if (barrier) value (unreachable)))
'''
WORKER = '''(let loop ((i 0) (result (absent)))
  (if (< i count)
      (loop (+ i 1) (present
        (test (hide-input count (vector->list (make-vector input0 (a-symbol)))))))
      (if (if (present? result)
              (and (= expected-kind 1) (= (optional-value result) expected-value))
              (= expected-kind 0)) 1 0)))'''


def specification(data):
    # The actual Chez reader supplies equality classes, including equivalent
    # exact rationals and distinct inexact, symbolic, compound and false datums.
    code = '''(import (chezscheme))
(define (emit value) (write value) (newline))
(define (read-i64)
  (let ((value (read)))
    (unless (and (integer? value) (exact? value) (<= (- (expt 2 63)) value (- (expt 2 63) 1)))
      (error 'earley "expected exact I64 input" value))
    (emit value)))
(read-i64) (read-i64)
(let ((value (read)))
  (when (eof-object? value) (error 'earley "missing expected value"))
  (cond ((eq? value #f) (emit 0) (emit 0))
        ((and (integer? value) (exact? value) (<= (- (expt 2 63)) value (- (expt 2 63) 1)))
         (emit 1) (emit value))
        (else (emit 2) (emit 0))))
(unless (eof-object? (read)) (error 'earley "extra input"))
'''
    with tempfile.TemporaryDirectory(prefix='earley-input-') as temporary:
        script = Path(temporary) / 'reader.scm'
        script.write_text(code)
        record = bounded_execute([os.environ.get('CHEZ', 'scheme'), '--script', script],
                                 temporary, os.environ, stdin=data.decode(), timeout=10)
    if record.get('error') or record.get('returncode') != 0 or record['stderr']:
        raise ValueError('Earley input reader failed: ' + str(record))
    count, size, kind, value = map(i64, record['stdout'].split())
    return dict(name='earley', count=exact_json_integer(count),
                inputs=list(map(exact_json_integer, (size, kind, value))), expected=1,
                result_kind='i64-list-values', barriers_per_iteration=1, setup_barriers=0,
                native_heap_bytes=1 << 30)


# ---- Bounded commands always clean their process group ----


def stop_group(process):
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def bounded_execute(command, cwd, environment, timeout=300, stdin=None):
    started = time.perf_counter()
    settings = ('BINARYEN_CORES', 'SNAIL_GC_HEAP_BYTES', 'SNAIL_GC_MIN_BYTES', 'SNAIL_GC_STATS',
                'SNAIL_NATIVE_GC_INTERVAL', 'EARLEY_SIZE', 'EARLEY_EXPECTED_KIND', 'EARLEY_EXPECTED')
    record = dict(command=list(map(str, command)), timeout=timeout,
                  environment={name: environment[name] for name in settings if name in environment})
    process = None
    try:
        process = subprocess.Popen(record['command'], cwd=cwd, env=environment,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, start_new_session=True)
        record['stdout'], record['stderr'] = process.communicate(stdin, timeout=timeout)
        record['returncode'] = process.returncode
    except subprocess.TimeoutExpired as error:
        record['error'] = str(error)
        stop_group(process)
        record['stdout'], record['stderr'] = process.communicate(timeout=10)
        record['returncode'] = process.returncode
    except (OSError, UnicodeError) as error:
        record['error'] = str(error)
    finally:
        if process:
            stop_group(process)
            process.wait(timeout=10)
        record['process_seconds'] = time.perf_counter() - started
    return record


# ---- Separate complete-tree, parser-boundary and storage probes ----

PROBE_COMMON = '''(define probe-mode (ref 0))
(define (emit-bool value) (emit (if value 1 0)))
(define (emit-optional-number value)
  (emit-bool (present? value)) (when (present? value) (emit (optional-value value))))
(define (emit-tree tree)
  (emit (length tree))
  (let loop ((parts tree))
    (unless (null? parts)
      (let* ((part (car parts)) (kind (part-kind part)))
        (emit kind)
        (if (= kind 0)
            (begin (emit (symbol-code (rule-name-symbol (part-name part))))
                   (emit (rule-name-number (part-name part))))
            (if (= kind 1) (emit (symbol-code (part-token part))) (emit-tree (part-child part)))))
      (loop (cdr parts)))))
(define (emit-trees value)
  (emit-bool (present? value))
  (when (present? value)
    (let ((trees (optional-value value)))
      (emit (length trees))
      (let loop ((trees trees))
        (unless (null? trees) (emit-tree (car trees)) (loop (cdr trees)))))))
(define (probe-lexer input)
  (earley-map (lambda (atom) (token atom (earley-list atom))) input))
(define (observe-parse parser input query)
  (let* ((parse (parser input)) (n (length input)))
    (emit n) (emit (symbol-code query))
    (emit-bool (parse->parsed? parse query 0 n))
    (emit-optional-number (parse->nb-trees parse query 0 n))
    (emit-trees (parse->trees parse query 0 n))))
(define documented-grammar
  (earley-list
    (definition (s-symbol) (earley-list (earley-list (x-symbol) (equals-symbol) (e-symbol))))
    (definition (e-symbol) (earley-list (earley-list (e-symbol) (plus-symbol) (e-symbol))
                                      (earley-list (v-symbol))))
    (definition (v-symbol) (earley-list (earley-list (v-symbol) (y-symbol)) '()))))
(define (probe-trees)
  (let ((parser (make-parser canonical-grammar probe-lexer)))
    (let loop ((n 0))
      (when (<= n 5)
        (observe-parse parser (vector->list (make-vector n (a-symbol))) (s-symbol))
        (loop (+ n 1))))
    (observe-parse parser (earley-list (a-symbol) (unknown-symbol) (a-symbol)) (s-symbol))
    (observe-parse parser (earley-list (s-symbol)) (s-symbol))
    (observe-parse parser (earley-list (a-symbol)) (a-symbol))
    (observe-parse parser (earley-list (a-symbol)) (unknown-symbol)))
  (let ((parser (make-parser documented-grammar probe-lexer)))
    (observe-parse parser (earley-list (x-symbol) (equals-symbol)) (s-symbol))
    (observe-parse parser (earley-list (x-symbol) (equals-symbol) (y-symbol)
                                     (plus-symbol) (y-symbol) (plus-symbol) (y-symbol)) (s-symbol))
    (observe-parse parser (earley-list (x-symbol) (y-symbol)) (s-symbol)))
  (observe-parse
    (make-parser (earley-list (definition (s-symbol)
      (earley-list (earley-list (a-symbol)) (earley-list (a-symbol))))) probe-lexer)
    (earley-list (a-symbol)) (s-symbol))
  (observe-parse
    (make-parser (earley-list (definition (s-symbol) (earley-list '()))) probe-lexer)
    '() (s-symbol)))
(define (emit-configuration value)
  (emit (configuration-size value))
  (let loop ((i 0))
    (when (< i (configuration-size value))
      (emit-optional-number (configuration-ref value i)) (loop (+ i 1)))))
(define (probe-configurations make-states get get* merge head next member adjoin adjoin* adjoin** union)
  (let* ((states (make-states 3 4)) (state (state-at states 2))
         (set (get* state 2 1)) (alias (get* state 2 1))
         (filtered (make-states 3 4)))
    (emit-bool (same-state? state (state-at states 2)))
    (emit-bool (not (same-state? state (state-at states 1))))
    (emit-bool (same-configuration? set alias))
    (emit-bool (not (present? (get state 2))))
    (emit-configuration set)
    (adjoin state set 1 0) (adjoin state set 1 1)
    (emit (state-work state)) (emit-configuration alias)
    (merge set) (emit-configuration set)
    (adjoin* states 2 (earley-list 1 1 2) 1)
    (emit-configuration set) (emit-configuration (optional-value (get state 2)))
    (emit-bool (present? (member state 1 0)))
    (emit-bool (not (present? (member state 1 2))))
    (emit-bool (adjoin** states filtered 2 1 0))
    (emit-bool (not (adjoin** states filtered 2 1 2)))
    (emit-configuration (optional-value (get (state-at filtered 2) 1)))
    (let ((joined (get* state 2 3)))
      (union state joined 3 set) (merge joined)
      (emit (head joined)) (emit-optional-number (next joined 0))
      (emit-optional-number (next joined 1)) (emit-configuration joined))))
(define (probe-closures)
  (let* ((calls (ref 0))
         (parser (make-parser canonical-grammar
           (lambda (input)
             (ref-set! calls (+ (ref-get calls) 1))
             (earley-map (lambda (atom)
               (token atom (if (= (ref-get calls) 1)
                 (earley-list (unknown-symbol) (a-symbol) (a-symbol))
                 (earley-list (unknown-symbol))))) input))))
         (parse (parser (earley-list (x-symbol) (y-symbol)))))
    (emit (ref-get calls))
    (emit-bool (parse->parsed? parse (s-symbol) 0 2))
    (emit-optional-number (parse->nb-trees parse (s-symbol) 0 2))
    (emit-trees (parse->trees parse (s-symbol) 0 2))
    (let rows ((i 0))
      (when (<= i 2)
        (let columns ((j i))
          (when (<= j 2)
            (emit-bool (parse->parsed? parse (s-symbol) i j))
            (emit-bool (parse->parsed? parse (a-symbol) i j))
            (columns (+ j 1))))
        (rows (+ i 1))))
    (observe-parse parser (earley-list (x-symbol)) (s-symbol))
    (emit (ref-get calls))))
(: probe (-> I64 I64))
(define (probe command)
  (ref-set! probe-mode command)
  (if (= command 0) (probe-trees)
      (if (= command 1) (begin ((make-parser canonical-grammar probe-lexer) '()) (unit))
          (probe-closures)))
  1)
'''
STRICT_PROBE = '''(define-extern emit "probe" "emit" (-> I64 Unit))
(define (configuration-size value) (vector-length (configuration-slots value)))
(define (same-configuration? first second)
  (vector-eq? (configuration-slots first) (configuration-slots second)))
(define (same-state? first second) (ref-eq? (state-head first) (state-head second)))
'''
ORIGINAL_PROBE = '''(define-syntax : (syntax-rules () ((_ . signature) (begin))))
(define (ref value) (vector value))
(define (ref-get value) (vector-ref value 0))
(define (ref-set! cell value) (vector-set! cell 0 value))
(define (unit) (if #f #f))
(define (present? value) (if value #t #f))
(define (optional-value value) value)
(define (part-kind value) (if (symbol? value) 1 (if (symbol? (car value)) 0 2)))
(define (part-name value) value)
(define (part-token value) value)
(define (part-child value) value)
(define rule-name-symbol car)
(define (rule-name-number value) (car (cdr value)))
(define (definition head rules) (cons head rules))
(define (token info classes) (cons info classes))
(define earley-list list)
(define earley-map map)
(define state-at vector-ref)
(define (state-work state) (vector-ref state 0))
(define configuration-size vector-length)
(define configuration-ref vector-ref)
(define same-configuration? eq?)
(define same-state? eq?)
(define canonical-grammar '((s (a) (s s))))
''' + ''.join(f"(define ({name}-symbol) '{atom})\n" for name, atom in zip(SYMBOLS, SYMBOL_TEXT)) + form(CHEZ_TYPES, '(define (symbol-code ')


def instrument_storage(kernel):
    anchor = '        (let* ((lexer      '
    code = '''        (when (= (ref-get probe-mode) 1)
          (probe-configurations make-states conf-set-get conf-set-get*
            conf-set-merge-new! conf-set-head conf-set-next conf-set-member?
            conf-set-adjoin conf-set-adjoin* conf-set-adjoin** conf-set-union))

'''
    return replace(kernel, anchor, code + anchor)


def probe_source(kernel, strict, prelude=''):
    if strict:
        return prelude + STRICT_TYPES + COMMON + STRICT_PROBE + PROBE_COMMON + instrument_storage(kernel)
    helpers = CHEZ_TYPES + COMMON + STRICT_PROBE[STRICT_PROBE.index('(define (configuration-size '):]
    return ('(import (chezscheme))\n' + helpers + PROBE_COMMON + instrument_storage(kernel)
            + '(define (emit value) (write value) (newline))\n(probe (read))\n')


def original_probe(kernel):
    return ('(import (chezscheme))\n' + ORIGINAL_PROBE + PROBE_COMMON + instrument_storage(kernel)
            + '(define (emit value) (write value) (newline))\n(probe (read))\n')


PROBE_HOST = '''import fs from 'node:fs';
import assert from 'node:assert/strict';
const [artifact, command] = process.argv.slice(2);
const values = [];
const {instance} = await WebAssembly.instantiate(fs.readFileSync(artifact),
  {probe: {emit: value => values.push(Number(value))}});
instance.exports.main();
assert.equal(instance.exports.probe(BigInt(command)), 1n);
console.log(JSON.stringify(values));
'''
NATIVE_HEADER = '''#include <stdint.h>
int64_t input_i64(int32_t index);
int32_t barrier(void);
void emit(int64_t value);
'''
NATIVE_PROVIDER = '''#include "provider.h"
#include <stdio.h>
#include <stdlib.h>
int64_t input_i64(int32_t index) {
    const char *keys[] = {"EARLEY_SIZE", "EARLEY_EXPECTED_KIND", "EARLEY_EXPECTED"};
    if (index < 0 || index > 2) abort();
    return strtoll(getenv(keys[index]), NULL, 10);
}
int32_t barrier(void) { return 1; }
void emit(int64_t value) { printf("%lld\\n", (long long)value); }
'''
NATIVE_ENTRY = '''#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t guest_call(int64_t) __asm__("wasm.EXPORT");
int main(int argc, char **argv) {
    native_host_init(argc, argv); native_module_init(); guest_main();
    int64_t result = guest_call(strtoll(argv[1], NULL, 10));
    printf("%lld\\n", (long long)result);
    return native_finish(0);
}
'''


# ---- Frozen preparation and cross-target observations ----


def checked_run(directory, label, command, environment, driver, stdin=None, timeout=300):
    record = bounded_execute(command, directory, environment, stdin=stdin, timeout=timeout)
    driver.save(directory / (label + '.json'), record)
    if record.get('error'):
        raise RuntimeError(str(record))
    driver.require_success(record)
    return record


def build_chez(directory, runner, tools, environment, driver):
    build, run = runner.chez_commands(directory, str(directory / 'program.scm'))
    checked_run(directory, 'chez-build', build, environment, driver)
    return [tools['CHEZ'], '--program', directory / 'program.so']


def build_wasm(directory, export, tools, environment, driver):
    checked_run(directory, 'strict-build', [driver.ROOT / 'scripts/build-strict', '--export', export,
                directory / 'strict.scm', directory / 'strict.wasm'], environment, driver, timeout=600)
    checked_run(directory, 'disassemble', [tools['WASM_DIS'], directory / 'strict.wasm', '-o',
                directory / 'strict.optimized.wat'], environment, driver)


def build_native(directory, export, environment, driver):
    (directory / 'provider.h').write_text(NATIVE_HEADER)
    (directory / 'provider.c').write_text(NATIVE_PROVIDER)
    (directory / 'entry.c').write_text(NATIVE_ENTRY.replace('EXPORT', export))
    module = 'probe' if export == 'probe' else 'benchmark'
    return checked_run(directory, 'native-build', [driver.ROOT / 'scripts/build-native', '--wasm',
        '--c-provider', module, directory / 'provider.h', directory / 'provider.c', '--entry-c',
        directory / 'entry.c', directory / 'strict.wasm', directory / 'native'], environment, driver, timeout=600)


def native_environment(spec, environment):
    return dict(environment, SNAIL_GC_HEAP_BYTES=str(spec.get('native_heap_bytes', 1 << 30)),
                **dict(zip(('EARLEY_SIZE', 'EARLEY_EXPECTED_KIND', 'EARLEY_EXPECTED'), map(str, spec['inputs']))))


def harness_fixtures():
    return [('canonical', '1 15 2674440', True), ('twice', '2 15 2674440', True),
            ('small', '1 4 5', True), ('exact-ratio', '1 4 10/2', True),
            ('wrong', '1 4 4', False), ('inexact', '1 4 5.0', False),
            ('false', '1 4 #f', False), ('symbol', '1 4 five', False),
            ('list', '1 4 (5)', False), ('vector', '1 4 #(5)', False),
            ('empty-input', '1 0 0', True), ('zero-count', '0 15 #f', True),
            ('zero-count-number', '0 15 0', False), ('negative-count', '-1 15 #f', True)]


def validate_harness(directory, runner, tools, environment, driver):
    checks = []
    for label, data, accepted in harness_fixtures():
        spec = specification(data.encode())
        path = directory / ('spec-' + label + '.json')
        driver.save(path, spec)
        for suffix in ('.raw.wasm', ''):
            command = [tools['NODE'], directory.parent / 'host.mjs', directory / ('strict.wasm' + suffix), path, '--validate']
            record = bounded_execute(command, directory, environment, timeout=180)
            checked = record.get('returncode') == 0 and not record.get('error')
            checks.append(dict(record, label=label, target='raw-wasm' if suffix else 'wasm', accepted=accepted))
            driver.save(directory / 'harness-validation.json', checks)
            if checked != accepted or (not accepted and "actual: '0'" not in record['stderr']):
                raise ValueError('Earley Wasm predicate differed: ' + label)
        record = checked_run(directory, 'native-' + label, [directory / 'native', spec['count']],
                             native_environment(spec, environment), driver, timeout=180)
        if record['stdout'].strip() != str(int(accepted)) or record['stderr']:
            raise ValueError('Earley native predicate differed: ' + label)
        for target in (directory, directory / 'same-source-chez'):
            record = checked_run(target, 'validation-' + label, [tools['CHEZ'], '--program', target / 'program.so'],
                                 environment, driver, stdin=data, timeout=180)
            rows = [line for line in record['stdout'].splitlines() if line.startswith('+!CSVLINE!+chez,earley:')]
            if len(rows) != 1:
                raise ValueError('Earley Chez validation lacks its original predicate record')
            status = not rows[0].endswith(',INCORRECT')
            if status != accepted or record['stderr']:
                raise ValueError('Earley Chez predicate differed: ' + label)


def read_tree(values):
    parts = []
    for _ in range(next(values)):
        kind = next(values)
        if kind == 0:
            parts.append([SYMBOL_TEXT[next(values)], next(values)])
        elif kind == 1:
            parts.append(SYMBOL_TEXT[next(values)])
        elif kind == 2:
            parts.append(read_tree(values))
        else:
            raise ValueError('unknown tree element tag')
    return parts


def read_observations(flat):
    values, observations = iter(flat), []
    while True:
        size = next(values, None)
        if size is None:
            return observations
        symbol, accepted = SYMBOL_TEXT[next(values)], bool(next(values))
        count = next(values) if next(values) else None
        trees = [read_tree(values) for _ in range(next(values))] if next(values) else None
        observations.append(dict(size=size, symbol=symbol, accepted=accepted, count=count, trees=trees))


def independent_trees(size):
    if size == 0:
        return []
    if size == 1:
        return [[['s', 1], [['a', 0], 'a']]]
    return [[['s', 2], left, right] for split in range(1, size)
            for left in independent_trees(split) for right in independent_trees(size - split)]


def check_tree_oracle(values, directory, driver):
    observations = read_observations(values)
    for size, observation in enumerate(observations[:6]):
        expected = independent_trees(size)
        if (observation['size'] != size or observation['accepted'] != bool(expected)
                or observation['count'] != len(expected)
                or sorted(map(json.dumps, observation['trees'])) != sorted(map(json.dumps, expected))):
            raise ValueError('Earley complete canonical trees differ from independent small oracle')
    for index, accepted in ((6, False), (7, True), (8, True), (9, False), (10, True), (11, True), (12, False), (13, True), (14, True)):
        if observations[index]['accepted'] != accepted:
            raise ValueError('Earley parser boundary differs')
    if observations[9]['trees'] is not None or observations[9]['count'] is not None:
        raise ValueError('unknown nonterminal must return the source false sentinel')
    if observations[13]['count'] != 2 or observations[14]['trees'] != [[['s', 1]]]:
        raise ValueError('duplicate production identity or empty production differs')
    driver.save(directory / 'complete-tree-observations.json', observations)


def configuration_oracle():
    def slots(values):
        return [len(values)] + [item for value in values for item in ([0] if value is None else [1, value])]
    merged = [-1, 1, 0, -1, -1, 1, -1, None]
    return ([1] * 4 + slots([None, -3, -1, -1, -1, None, None, None])
            + [1] + slots([-1, -3, -1, 1, 0, 1, -1, None]) + slots(merged) + slots(merged)
            + slots([1, -3, -1, 1, 1, None, -1, None]) + [1] * 4
            + slots([-1, -3, -1, 0, 0, -1, None, None]) + [0, 1, 1, 1, -1]
            + slots([2, 1, 0, -1, -1, 1, -1, None]))


def validate_probes(directory, original, adapted, runner, tools, environment, driver):
    probe = directory / 'probe'
    probe.mkdir()
    (probe / 'strict.scm').write_text(probe_source(adapted, True, driver.PRELUDE))
    (probe / 'host.mjs').write_text(PROBE_HOST)
    build_wasm(probe, 'probe', tools, environment, driver)
    build_native(probe, 'probe', environment, driver)
    for name, source in (('original', original_probe(original)), ('adapted', probe_source(adapted, False))):
        target = probe / name
        target.mkdir()
        (target / 'program.scm').write_text(source)
        build_chez(target, runner, tools, environment, driver)
    for command in range(3):
        outputs = {}
        for name in ('original', 'adapted'):
            target = probe / name
            record = checked_run(target, f'case-{command}', [tools['CHEZ'], '--program', target / 'program.so'],
                                 environment, driver, stdin=str(command))
            outputs[name] = list(map(int, record['stdout'].split()))
        for suffix in ('.raw.wasm', ''):
            name = 'raw-wasm' if suffix else 'wasm'
            record = checked_run(probe, f'{name}-{command}', [tools['NODE'], probe / 'host.mjs',
                                 probe / ('strict.wasm' + suffix), command], environment, driver)
            outputs[name] = json.loads(record['stdout'])
        record = checked_run(probe, f'native-{command}', [probe / 'native', command], environment, driver)
        native = list(map(int, record['stdout'].split()))
        if not native or native[-1] != 1:
            raise ValueError('native Earley probe returned an invalid status')
        outputs['native'] = native[:-1]
        driver.save(probe / f'comparison-{command}.json', outputs)
        if any(value != outputs['original'] for value in outputs.values()):
            raise ValueError('Earley complete probe observations differ: ' + str(command))
        if command == 0:
            check_tree_oracle(outputs['original'], directory, driver)
        if command == 1 and outputs['original'] != configuration_oracle():
            raise ValueError('Earley configuration transitions differ from independent slot model')


def prepare_case(files, output, runner, tools, environment, driver):
    directory = output / 'earley'
    directory.mkdir()
    spec = specification(files['inputs/earley.input'])
    driver.write_case_sources('earley', files, directory, spec, runner)
    adapted, original_kernel, adapted_kernel = driver.matched_chez_source('earley', directory)
    driver.save(directory / 'source-edits.json', adaptation(original_kernel)[1])
    (directory / 'original-kernel.scm').write_text(original_kernel)
    (directory / 'adapted-kernel.scm').write_text(adapted_kernel)
    control = directory / 'same-source-chez'
    control.mkdir()
    (control / 'program.scm').write_text(adapted)
    build_wasm(directory, 'bench', tools, environment, driver)
    build_native(directory, 'bench', environment, driver)
    for target in (directory, control):
        build_chez(target, runner, tools, environment, driver)
    validate_harness(directory, runner, tools, environment, driver)
    validate_probes(directory, original_kernel, adapted_kernel, runner, tools, environment, driver)
    driver.save(directory / 'source-proof.json', dict(complete_original_restored=True,
        same_adapted_kernel_in_chez_and_strict=True, unchanged_original_harness=True,
        canonical_count=spec['count'], canonical_size=spec['inputs'][0], source_materializes_complete_trees=True,
        finite_atom_vocabulary=list(SYMBOL_TEXT), lexical_user_info='the same finite atom vocabulary',
        append_helper='temporary reversed prefix, then copied forward prefix onto the original shared suffix',
        native_heap_bytes=spec['native_heap_bytes'],
        original_kernel_sha256=hashlib.sha256(original_kernel.encode()).hexdigest(),
        adapted_kernel_sha256=hashlib.sha256(adapted_kernel.encode()).hexdigest()))
    return dict(name='earley', status='ready', spec=spec, systems=['strict', 'chez', 'chez-adapted'],
                hashes={str(path.relative_to(directory)): driver.digest(path)
                        for path in directory.rglob('*') if path.is_file()})
