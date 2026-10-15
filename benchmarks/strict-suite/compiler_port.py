"""Adapt the complete upstream compiler; keep source extent and edits auditable."""

import hashlib
import json
import re
from pathlib import Path

from data_ports import replace


# ---- Complete source extents include character literals and quoted forms ----

# In particular, #\( and #\) are atoms in the upstream reader. Treating their
# parentheses as source delimiters can silently remove definitions after it.
TOKEN = re.compile(r';[^\n]*|"(?:[^"\\]|\\.)*"|#\\(?:[^()\s]+|[()])|#\(|,@|[()]|[\'`,]|[^\s()\'`,;]+')


def tokens(source):
    return [token for token in TOKEN.finditer(source) if not token[0].startswith(';')]


def datum_end(items, start):
    token = items[start][0]
    if token in ("'", '`', ',', ',@'):
        return datum_end(items, start + 1)
    if token not in ('(', '#('):
        if token == ')':
            raise ValueError('unexpected source close parenthesis')
        return start + 1
    index = start + 1
    while items[index][0] != ')':
        index = datum_end(items, index)
    return index + 1


def source_forms(source):
    items, index = tokens(source), 0
    while index < len(items):
        end = datum_end(items, index)
        yield items[index].start(), items[end - 1].end()
        index = end


def named_form(source, prefix):
    matches = [(start, end) for start, end in source_forms(source)
               if source.startswith(prefix, start)]
    if len(matches) != 1:
        raise ValueError(f'expected one complete compiler form starting with {prefix!r}')
    start, end = matches[0]
    return source[start:end]


def kernel(source):
    # Remove exactly the imports and harness, wherever the harness occurs.
    # Every other source byte remains, including comments and later forms.
    for prefix in ('(import ', '(define (run-benchmark)'):
        source = replace(source, named_form(source, prefix), '')
    return source


def source_inventory(source):
    result = []
    for start, end in source_forms(source):
        text = source[start:end]
        heading = re.match(r'\(define\s+(?:\(\s*)?([^\s()]+)', text)
        result.append(dict(name=heading[1] if heading else None,
                           start=start, end=end,
                           line=source.count('\n', 0, start) + 1,
                           sha256=hashlib.sha256(text.encode()).hexdigest()))
    return result


# ---- Original input and the complete ordered assembly predicate ----

def specification(data):
    source = data.decode()
    forms = [source[start:end] for start, end in source_forms(source)]
    if len(forms) != 5:
        raise ValueError('compiler input requires count, program, target, option and expected output')
    expected = tokens(forms[4])[1:-1]
    lines = [json.loads(token[0]) for token in expected]
    return dict(name='compiler', count=int(forms[0]), program=forms[1],
                target=forms[2], option=forms[3], expected_lines=lines,
                expected=1, barriers_per_iteration=3, setup_barriers=0,
                input_sha256=hashlib.sha256(data).hexdigest())


def representations():
    return Path(__file__).with_name('compiler-data.scm').read_text()


# ---- Collection forms retain the source algorithms and record every edit ----

COLLECTION_NAMES = '''make-counter pos-in-list string-pos-in-list nth-after pair-up
my-last-pair sort-list lst->vector vector->lst lst->string string->lst make-gnode
gnode-label gnode-edges transitive-closure gnode-find topological-sort remove-no-edges
remove-cycle list->set set->list set-empty set-empty? set-member? set-singleton
set-adjoin set-remove set-equal? set-difference set-union set-intersection n-ary
set-keep set-every? set-map list->queue queue->list queue-empty queue-empty?
queue-get! queue-put!'''.split()


def collection_form(source, name):
    ending = ')' if name in ('set-empty', 'queue-empty') else ' '
    return named_form(source, '(define (' + name + ending)


def collection_changes(name):
    # These edits change representation, arity or visible result propagation.
    # The shared substitutions below only select typed list/control operations.
    return {
        'make-counter': [
            ('(lambda ()', '(let ((next (ref next)))\n    (lambda ()'),
            ('(< next limit)', '(< (ref-get next) limit)'),
            ('(let ((result next)) (set! next (+ next 1)) result)',
             '(let ((result (ref-get next)))\n'
             '          (ref-set! next (+ (ref-get next) 1))\n'
             '          (compiler-success result))'),
            ('(limit-error))))', '(limit-error)))))')],
        'pos-in-list': [
            ('(pos-in-list x l)', '(pos-in-list same? x l)'),
            ('((not (pair? l)) #f)', '((not (pair? l)) (compiler-none))'),
            ('((eq? (car l) x) i)', '((same? (car l) x) (compiler-some i))')],
        'string-pos-in-list': [
            ('((not (pair? l)) #f)', '((not (pair? l)) (compiler-none))'),
            ('((string=? (car l) x) i)', '((string=? (car l) x) (compiler-some i))')],
        'pair-up': [
            ('(cons (car l1) (car l2))', '(compiler-make-pair (car l1) (car l2))')],
        'lst->vector': [
            ('(v (make-vector n))',
             '(v (if (= n 0) (empty-vector) (make-vector n (car l))))')],
        'make-gnode': [
            ('(vector label edges)', '(compiler-dependency-node (ref label) edges)')],
        'gnode-label': [
            ('(vector-ref x 0)', '(ref-get (compiler-dependency-label-cell x))')],
        'gnode-edges': [
            ('(vector-ref x 1)', '(compiler-dependency-edges x)')],
        'transitive-closure': [
            ('(define changed? #f)', '(define changed? (ref #f))'),
            ('(set-union\n      edges\n      (apply set-union\n'
             '             (map (lambda (label) (gnode-edges (gnode-find label graph)))\n'
             '                  (set->list edges))))',
             '(set-union\n      compiler-variable-eq?\n'
             '      (list edges\n'
             '            (set-union\n'
             '             compiler-variable-eq?\n'
             '             (map (lambda (label)\n'
             '                    (gnode-edges (compiler-option-value (gnode-find label graph))))\n'
             '                  (set->list edges)))))'),
            ('(set-equal? new-edges (gnode-edges x))',
             '(set-equal? compiler-variable-eq? new-edges (gnode-edges x))'),
            ('(set! changed? #t)', '(ref-set! changed? #t)'),
            ('(if changed?', '(if (ref-get changed?)')],
        'gnode-find': [
            ('((null? l) #f)', '((null? l) (compiler-none))'),
            ('((eq? (gnode-label (car l)) label) (car l))',
             '((compiler-variable-eq? (gnode-label (car l)) label) (compiler-some (car l)))')],
        'topological-sort': [
            ('(or (remove-no-edges graph) (remove-cycle graph))',
             '(match (remove-no-edges graph)\n'
             '                         ((compiler-none) (remove-cycle graph))\n'
             '                         ((compiler-some nodes) nodes))'),
            ('(set-difference (gnode-edges x) labels)',
             '(set-difference compiler-variable-eq? (gnode-edges x) (list labels))'),
            ('(set-difference graph to-remove)',
             '(set-difference compiler-dependency-eq? graph (list to-remove))')],
        'remove-no-edges': [
            ('(if (set-empty? nodes-with-no-edges) #f nodes-with-no-edges)',
             '(if (set-empty? nodes-with-no-edges) (compiler-none) (compiler-some nodes-with-no-edges))')],
        'remove-cycle': [
            ('(set-equal? (gnode-edges x) edges)',
             '(set-equal? compiler-variable-eq? (gnode-edges x) edges)'),
            ('(set-member? (gnode-label x) edges)',
             '(compiler-present? (set-member? compiler-variable-eq? (gnode-label x) edges))'),
            ('(set-member? (gnode-label (car l)) edges)',
             '(compiler-present? (set-member? compiler-variable-eq? (gnode-label (car l)) edges))')],
        'set-member?': [
            ('(set-member? x set)', '(set-member? same? x set)'),
            ('(memq x set)', '(compiler-memq same? x set)')],
        'set-adjoin': [
            ('(set-adjoin set x)', '(set-adjoin same? set x)'),
            ('(memq x set)', '(compiler-present? (compiler-memq same? x set))')],
        'set-remove': [
            ('(set-remove set x)', '(set-remove same? set x)'),
            ('(eq? (car set) x)', '(same? (car set) x)'),
            ('(set-remove (cdr set) x)', '(set-remove same? (cdr set) x)')],
        'set-equal?': [
            ('(set-equal? s1 s2)', '(set-equal? same? s1 s2)'),
            ('(memq (car s1) s2)', '(compiler-present? (compiler-memq same? (car s1) s2))'),
            ('(set-equal? (cdr s1) (set-remove s2 (car s1)))',
             '(set-equal? same? (cdr s1) (set-remove same? s2 (car s1)))')],
        'set-difference': [
            ('(set-difference set . other-sets)', '(set-difference same? set other-sets)'),
            ('(memq (car s1) s2)', '(compiler-present? (compiler-memq same? (car s1) s2))')],
        'set-union': [
            ('(set-union . sets)', '(set-union same? sets)'),
            ('(memq (car s1) s2)', '(compiler-present? (compiler-memq same? (car s1) s2))')],
        'set-intersection': [
            ('(set-intersection set . other-sets)', '(set-intersection same? set other-sets)'),
            ('(memq (car s1) s2)', '(compiler-present? (compiler-memq same? (car s1) s2))')],
        'set-keep': [
            ('(cons (car set) (set-keep keep? (cdr set)))',
             '(let ((first (car set))) (cons first (set-keep keep? (cdr set))))')],
        'set-map': [
            ('(cons (proc (car set)) (set-map proc (cdr set)))',
             '(let ((first (proc (car set)))) (cons first (set-map proc (cdr set))))')],
        'list->queue': [
            ("(cons list (if (pair? list) (my-last-pair list) '()))",
             "(compiler-make-pair list (if (pair? list) (my-last-pair list) '()))")],
        'queue->list': [('(car queue)', '(compiler-pair-first queue)')],
        'queue-empty': [("(cons '() '())", "(compiler-make-pair '() '())")],
        'queue-empty?': [('(car queue)', '(compiler-pair-first queue)')],
        'queue-get!': [
            ('(compiler-internal-error "queue-get!, queue is empty")',
             '(compiler-internal-error "queue-get!, queue is empty" (compiler-empty))'),
            ('(caar queue)', '(compiler-car (compiler-pair-first queue))'),
            ('(set-car! queue (cdar queue))',
             '(compiler-pair-first-set! queue (compiler-cdr (compiler-pair-first queue)))'),
            ("(if (null? (car queue)) (set-cdr! queue '()))",
             "(when (null? (car queue)) (compiler-pair-rest-set! queue '()))"),
            ('        x)))', '        (compiler-success x))))'),
            ('(car queue)', '(compiler-pair-first queue)', 2)],
        'queue-put!': [
            ('(car queue)', '(compiler-pair-first queue)'),
            ('(set-car! queue entry)', '(compiler-pair-first-set! queue entry)'),
            ('(set-cdr! (cdr queue) entry)', '(compiler-set-cdr! (compiler-pair-rest queue) entry)'),
            ('(set-cdr! queue entry)', '(compiler-pair-rest-set! queue entry)')],
    }.get(name, [])


def collection_adaptation(source):
    original, ledger = source, []
    operations = {'cons': 'compiler-cons', 'car': 'compiler-car', 'cdr': 'compiler-cdr',
                  'cddr': 'compiler-cddr', 'null?': 'compiler-null?', 'pair?': 'compiler-pair?',
                  'list': 'compiler-list', 'length': 'compiler-length', 'map': 'compiler-map',
                  'cond': 'compiler-cond'}
    for name in COLLECTION_NAMES:
        before = collection_form(source, name)
        after, changes = before, []
        for change in collection_changes(name):
            old, new, *counts = change
            count = counts[0] if counts else 1
            after = replace(after, old, new, count)
            changes.append(dict(before=old, after=new, count=count))
        for old, new in [("'()", '(compiler-empty)'),
                         *((f'({old} ', f'({new} ') for old, new in operations.items())]:
            count = after.count(old)
            if count:
                after = replace(after, old, new, count)
                changes.append(dict(before=old, after=new, count=count))
        source = replace(source, before, after)
        ledger.append(dict(name=name, before=before, after=after, changes=changes,
                           source_sha256=hashlib.sha256(before.encode()).hexdigest(),
                           adapted_sha256=hashlib.sha256(after.encode()).hexdigest()))
    restored = source
    for entry in reversed(ledger):
        restored = replace(restored, entry['after'], entry['before'])
    if restored != original:
        raise ValueError('compiler collection adaptation did not restore every source byte')
    return source, ledger


# ---- Source diagnostics finish their output before returning an abort ----

DIAGNOSTIC_NAMES = ('compiler-error', 'compiler-internal-error', 'compiler-limitation-error')


def diagnostic_adaptation(source):
    original, ledger = source, []
    for name in DIAGNOSTIC_NAMES:
        before = named_form(source, '(define (' + name + ' ')
        changes = [('(' + name + ' msg . args)', '(' + name + ' msg args)'),
                   ('(for-each ', '(compiler-for-each '),
                   ('(write x)', '(write-datum x (current-output-port))'),
                   ('(compiler-abort)', '(compiler-abort-result)')]
        changes.append(('(display ', '(write-string ', before.count('(display ')))
        after, edits = before, []
        for old, new, *counts in changes:
            count = counts[0] if counts else 1
            after = replace(after, old, new, count)
            edits.append(dict(before=old, after=new, count=count))
        source = replace(source, before, after)
        ledger.append(dict(name=name, before=before, after=after, changes=edits))
    restored = source
    for entry in reversed(ledger):
        restored = replace(restored, entry['after'], entry['before'])
    if restored != original:
        raise ValueError('compiler diagnostic adaptation did not restore every source byte')
    return source, ledger


def diagnostic_contracts():
    # Strings use the scalar text writer directly; argument data uses the
    # general writer. The original ordered newline/space/argument work remains.
    return ''.join(f'(: {name} (All (T) (-> String (CompilerList Datum) (CompilerResult T))))\n'
                   for name in DIAGNOSTIC_NAMES)
