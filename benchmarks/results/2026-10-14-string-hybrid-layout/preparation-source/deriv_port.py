"""Preserve deriv's pair spines, finite atoms and deliberately wrong quotient rule."""

from dataclasses import dataclass
import re

from data_ports import replace


# ---- Closed datums and their setup-only scalar encoding ----

# Every original pair remains one pair node. Atoms are shared before timing;
# in particular, returning derivative zero/one does not allocate number boxes.
# Prefix tags 3 and 4 carry an integer or two recursively encoded datums.
ATOMS = ((0, 'false', '#f'), (1, 'true', '#t'), (2, 'empty', None),
         (5, 'x', 'x'), (6, 'a', 'a'), (7, 'b', 'b'),
         (8, 'plus', '+'), (9, 'minus', '-'), (10, 'times', '*'), (11, 'divide', '/'))
ATOM_TAGS = {value: tag for tag, name, value in ATOMS}


@dataclass(frozen=True)
class Pair:
    first: object
    rest: object


def pair_spine(values, tail=None):
    for value in reversed(values):
        tail = Pair(value, tail)
    return tail


def read_atom(token):
    if re.fullmatch(r'[+-]?\d+', token):
        value = int(token)
        if not -(2 ** 63) <= value < 2 ** 63:
            raise ValueError('deriv integer outside I64')
        return value
    if token not in ATOM_TAGS:
        raise ValueError('datum outside deriv finite vocabulary: ' + token)
    return token


def read_datum(token, tokens):
    if token != '(':
        return read_atom(token)
    values = []
    for token in tokens:
        if token == ')':
            return pair_spine(values)
        if token == '.' and values:
            tail = read_datum(next(tokens), tokens)
            if next(tokens) != ')':
                raise ValueError('dotted datum must end after its tail')
            return pair_spine(values, tail)
        values.append(read_datum(token, tokens))
    raise ValueError('unclosed deriv datum')


def read_datums(text):
    tokens = iter(re.findall(r'\(|\)|[^\s()]+', re.sub(r';[^\n]*', '', text)))
    try:
        return [read_datum(token, tokens) for token in tokens]
    except StopIteration as error:
        raise ValueError('incomplete deriv datum') from error


def encode(value):
    if isinstance(value, Pair):
        return [4, *encode(value.first), *encode(value.rest)]
    if isinstance(value, int):
        return [3, value]
    return [ATOM_TAGS[value]]


def specification(data):
    count, value, expected = read_datums(data.decode())
    if not isinstance(count, int):
        raise ValueError('deriv repetition count must be an integer')
    return dict(name='deriv', count=count, inputs=[encode(value), encode(expected)],
                expected=1, barriers_per_iteration=1,
                input_representation='closed-datum-prefix', setup_barriers=0)


# ---- One typed node per source pair, with shared atom constants ----

COMMON = '''(define (datum-cadr value) (datum-car (datum-cdr value)))
(define (datum-caddr value) (datum-car (datum-cdr (datum-cdr value))))
(define (datum-list3 a b c)
  (datum-cons a (datum-cons b (datum-cons c datum-empty))))
(define (datum-list4 a b c d)
  (datum-cons a (datum-cons b (datum-cons c (datum-cons d datum-empty)))))
(define (datum-map f values)
  (if (datum-null? values) datum-empty
      (datum-cons (f (datum-car values)) (datum-map f (datum-cdr values)))))
(define (datum-equal? left right)
  (let ((tag (datum-tag left)))
    (and (= tag (datum-tag right))
         (cond ((= tag 3) (= (datum-number-value left) (datum-number-value right)))
               ((= tag 4) (and (datum-equal? (datum-car left) (datum-car right))
                              (datum-equal? (datum-cdr left) (datum-cdr right))))
               (else #t)))))
'''


def atom_constants():
    return ''.join(f'(define datum-{name} (make-datum-{name}))\n' for tag, name, value in ATOMS)


def symbol_predicates():
    return ''.join(f'(define (datum-{name}? value) (= (datum-tag value) {tag}))\n'
                   for tag, name, value in ATOMS if tag >= 5)


def strict_predicates():
    # Timed classification tests a constructor directly. Prefix tags belong
    # to setup decoding and the once-per-run complete result comparison.
    # Strict match deliberately requires every constructor, without wildcards.
    patterns = [(tag, 'make-datum-' + name) for tag, name, value in ATOMS]
    patterns += [(3, 'make-datum-number number'), (4, 'datum-cons first rest')]
    predicates = [('pair', 4), ('null', 2)] + [(name, tag) for tag, name, value in ATOMS if tag >= 5]
    result = []
    for name, wanted in predicates:
        arms = ''.join(f"    (({pattern}) {'#t' if tag == wanted else '#f'})\n" for tag, pattern in patterns)
        result.append(f'(define (datum-{name}? value)\n  (match value\n' + arms + '))\n')
    return ''.join(result)


def strict_types():
    variants = ''.join(f'  (make-datum-{name})\n' for tag, name, value in ATOMS)
    tags = ''.join(f'    ((make-datum-{name}) {tag})\n' for tag, name, value in ATOMS)
    return ('(define-data DerivDatum\n' + variants
            + '  (make-datum-number (value I64 datum-number-value))\n'
            + '  (datum-cons (first DerivDatum datum-car) (rest DerivDatum datum-cdr)))\n'
            + '(define (datum-tag value)\n  (match value\n' + tags
            + '    ((make-datum-number number) 3)\n    ((datum-cons first rest) 4)))\n'
            + atom_constants() + '(define datum-zero (make-datum-number 0))\n'
            + '(define datum-one (make-datum-number 1))\n' + strict_predicates() + COMMON)


CHEZ_STORAGE = '''(define (datum-tag value) (vector-ref value 0))
(define (datum-pair? value) (= (datum-tag value) 4))
(define (datum-null? value) (= (datum-tag value) 2))
(define (make-datum-number value) (vector 3 value))
(define (datum-cons first rest) (vector 4 first rest))
(define (datum-number-value value)
  (if (= (datum-tag value) 3) (vector-ref value 1) (error #f "not a number datum")))
(define (datum-car value)
  (if (= (datum-tag value) 4) (vector-ref value 1) (error #f "not a pair datum")))
(define (datum-cdr value)
  (if (= (datum-tag value) 4) (vector-ref value 2) (error #f "not a pair datum")))
(define (unreachable) (error #f "No derivation method available"))
'''


def chez_helpers():
    constructors = ''.join(f'(define (make-datum-{name}) (vector {tag}))\n' for tag, name, value in ATOMS)
    return (CHEZ_STORAGE + constructors + atom_constants()
            + '(define datum-zero (make-datum-number 0))\n'
            + '(define datum-one (make-datum-number 1))\n' + symbol_predicates() + COMMON + chez_conversion())


def chez_conversion():
    atoms = ''.join(f"        ((equal? value '{'()' if value is None else value}) datum-{name})\n"
                    for tag, name, value in ATOMS)
    return ('''(define (datum-from-scheme value)
  (cond ((pair? value) (datum-cons (datum-from-scheme (car value)) (datum-from-scheme (cdr value))))
        ((integer? value) (make-datum-number value))
''' + atoms + '''        (else (error #f "datum outside deriv finite vocabulary"))))
''')


def chez_output_conversion():
    atoms = ''.join(f"          ((= tag {tag}) '{'()' if value is None else value})\n"
                    for tag, name, value in ATOMS)
    return ('''(define (datum-to-scheme value)
  (let ((tag (datum-tag value)))
    (cond ((= tag 3) (datum-number-value value))
          ((= tag 4) (cons (datum-to-scheme (datum-car value)) (datum-to-scheme (datum-cdr value))))
''' + atoms + '''          (else (error #f "invalid deriv datum")))))
''')


# ---- Mechanical edits preserve the complete upstream derivative body ----

def kernel(source):
    source = replace(source, "(if (eq? a 'x) 1 0)", '(if (datum-x? a) datum-one datum-zero)')
    for symbol, name in (('+', 'plus'), ('-', 'minus'), ('*', 'times'), ('/', 'divide')):
        source = replace(source, f"(eq? (car a) '{symbol})", f'(datum-{name}? (car a))')
    source = replace(source, "(list '*\n                           (caddr a)",
                     "(datum-list4 '*\n                           (caddr a)")
    for old, new, count in (('pair?', 'datum-pair?', 1), ('car', 'datum-car', 4),
                            ('cdr', 'datum-cdr', 3), ('cadr', 'datum-cadr', 2),
                            ('caddr', 'datum-caddr', 4), ('cons', 'datum-cons', 3),
                            ('map', 'datum-map', 3), ('list', 'datum-list3', 5)):
        source = replace(source, '(' + old + ' ', '(' + new + ' ', count)
    for symbol, name, count in (('+', 'plus', 2), ('-', 'minus', 2), ('*', 'times', 2), ('/', 'divide', 3)):
        source = replace(source, "'" + symbol, 'datum-' + name, count)
    return replace(source, '(error #f "No derivation method available")', '(unreachable)')


def adapt_chez_harness(source, reverse=False):
    edits = [('(input1 (read))', '(input1 (datum-from-scheme (read)))'),
             ('(output (read))', '(output (datum-from-scheme (read)))'),
             ('(result #f)', '(result datum-false)'),
             ('(equal? result output)', '(datum-equal? result output)')]
    for original, adapted in edits:
        source = replace(source, adapted if reverse else original, original if reverse else adapted)
    return source


# ---- Runtime input construction and the original current-result loop ----

INPUTS = '''(define-extern datum-input-length "benchmark" "vector_length" (-> I32 I64))
(define-extern datum-input-token "benchmark" "vector_i64" (-> I32 I64 I64))
(define (next-datum-token source position)
  (let ((i (ref-get position)))
    (if (< i (datum-input-length source))
        (begin (ref-set! position (+ i 1)) (datum-input-token source i))
        (unreachable))))
(define (read-input-datum source)
  (let* ((position (ref 0)) (value (read-datum source position)))
    (if (= (ref-get position) (datum-input-length source)) value (unreachable))))
'''


def input_prelude():
    atoms = ''.join(f'          ((= tag {tag}) datum-{name})\n' for tag, name, value in ATOMS)
    return (INPUTS + '''(define (read-datum source position)
  (let ((tag (next-datum-token source position)))
    (cond ((= tag 3) (make-datum-number (next-datum-token source position)))
          ((= tag 4) (let* ((first (read-datum source position))
                           (rest (read-datum source position))) (datum-cons first rest)))
''' + atoms + '''          (else (unreachable)))))
''')


INPUT_BINDINGS = '''(define input0 (read-input-datum (ann 0 I32)))
(define expected (read-input-datum (ann 1 I32)))
'''
WORKER = '''(if (datum-equal?
    (let loop ((i 0) (result datum-false))
      (if (< i count) (loop (+ i 1) (deriv (hide count input0))) result))
    expected) 1 0)'''
PROBE = '''(: deriv-probe (-> I64 I64))
(define (deriv-probe ignored)
  (if (datum-equal? (deriv input0) expected) 1 0))
(unit)
'''


# ---- Separate complete-expression, predicate and failure probes ----

def fixtures():
    # Literal expected trees independently spell out the source rule; the
    # original Chez kernel must agree before adapted/strict checks are accepted.
    return [
        ('variable', 'x', '1'), ('other-variable', 'a', '0'), ('integer', '-7', '0'),
        ('empty-atom', '()', '0'), ('operator-atom', '*', '0'),
        ('false-atom', '#f', '0'), ('true-atom', '#t', '0'),
        ('empty-sum', '(+)', '(+)'), ('empty-difference', '(-)', '(-)'),
        ('sum-order', '(+ x b -2 x)', '(+ 1 0 0 1)'),
        ('difference', '(- x 3)', '(- 1 0)'),
        ('empty-product', '(*)', '(* (*) (+))'),
        ('unary-product', '(* x)', '(* (* x) (+ (/ 1 x)))'),
        ('nested-product', '(* (+ x a) (* b x))',
         '(* (* (+ x a) (* b x)) (+ (/ (+ 1 0) (+ x a)) (/ (* (* b x) (+ (/ 0 b) (/ 1 x))) (* b x))))'),
        ('quotient-numerator', '(/ x a)', '(- (/ 1 a) (/ x (* a a 0)))'),
        ('quotient-denominator', '(/ a x)', '(- (/ 0 x) (/ a (* x x 1)))'),
        ('quotient-compound', '(/ (* a x) (+ x b))',
         '(- (/ (* (* a x) (+ (/ 0 a) (/ 1 x))) (+ x b)) (/ (* a x) (* (+ x b) (+ x b) (+ 1 0))))'),
        ('quotient-ignored-extra', '(/ x a (b x))', '(- (/ 1 a) (/ x (* a a 0)))'),
        ('quotient-ignored-tail', '(/ x a . b)', '(- (/ 1 a) (/ x (* a a 0)))'),
    ]


def invalid_fixtures():
    return [('unknown-symbol-head', '(a x)'), ('number-head', '(3 x)'),
            ('pair-head', '((+ x) a)'), ('empty-head', '(() x)'),
            ('quotient-no-operands', '(/)'), ('quotient-one-operand', '(/ x)'),
            ('quotient-improper-operands', '(/ x . a)'),
            ('sum-improper', '(+ x . a)'), ('difference-improper', '(- x . b)'),
            ('product-improper', '(* x . a)')]


def predicate_fixtures():
    expression = '(* (+ x a) (* b x))'
    correct = fixtures()[13][2]
    return [('wrong-atom', expression, correct.replace('(/ 0 b)', '(/ 1 b)')),
            ('wrong-operator', expression, correct.replace('(/ 0 b)', '(+ 0 b)')),
            ('wrong-symbol', expression, correct.replace('(/ 0 b)', '(/ 0 a)')),
            ('wrong-order', expression, correct.replace('(+ 1 0)', '(+ 0 1)')),
            ('short-spine', expression, correct.replace('(+ (/ 0 b) (/ 1 x))', '(+ (/ 0 b))')),
            ('long-spine', expression, correct.replace('(+ (/ 0 b) (/ 1 x))', '(+ (/ 0 b) (/ 1 x) 0)')),
            ('improper-spine', expression, correct.replace('(+ 1 0)', '(+ 1 . 0)'))]


def probe_specification(expression, expected):
    return dict(name='deriv-probe', count=1, export='deriv-probe',
                inputs=[encode(read_datums(expression)[0]), encode(read_datums(expected)[0])],
                expected=1, barriers_per_iteration=0)


def probe_input(expression, expected, extract=False):
    return f'{0 if extract else 1}\n{expression}\n{expected}\n'


def chez_probe_source(kernel_source, adapted):
    helpers = chez_helpers() + chez_output_conversion() if adapted else ''
    input_value = '(datum-from-scheme input)' if adapted else 'input'
    output_value = '(datum-to-scheme actual)' if adapted else 'actual'
    comparison = '(datum-equal? actual (datum-from-scheme expected))' if adapted else '(equal? actual expected)'
    return ('(import (chezscheme))\n' + helpers + kernel_source
            + f'''(let* ((action (read)) (input (read)) (expected (read))
         (actual (deriv {input_value})))
  (write (if (= action 0) {output_value} {comparison}))
  (newline))
''')


# ---- Sharing checks run only in the two separate Chez probe programs ----

SHARING = '''(define (sharing-checks product quotient)
  (let* ((p (deriv product)) (q (deriv quotient))
         (terms (CDR (CADDR p))) (denominator (CADDR quotient)))
    (list
     (eq? (CADR p) product)
     (eq? (CADDR (CAR terms)) (CADR product))
     (eq? (CADDR (CADR terms)) (CADDR product))
     (not (eq? p (deriv product)))
     (not (eq? (CDR p) (CDR (deriv product))))
     (eq? (CADR (CADDR q)) (CADR quotient))
     (eq? (CADDR (CADR q)) denominator)
     (eq? (CADR (CADDR (CADDR q))) denominator)
     (eq? (CADDR (CADDR (CADDR q))) denominator))))
'''


def chez_sharing_source(kernel_source, adapted):
    body = SHARING
    for operation in ('CAR', 'CDR', 'CADR', 'CADDR'):
        body = body.replace(operation, ('datum-' if adapted else '') + operation.lower())
    value = '(datum-from-scheme (read))' if adapted else '(read)'
    return ('(import (chezscheme))\n' + (chez_helpers() if adapted else '') + kernel_source + body
            + f'(let* ((product {value}) (quotient {value}))\n'
            + '  (write (sharing-checks product quotient)) (newline))\n')
