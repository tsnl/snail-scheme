"""Authored SFIR examples; no Scheme expansion or source translation."""

MODULES = {
    'test/shared.sfir': '''(library (test shared)
  (export cell Box box box-value choose)
  (import (sfir primitive))
  (define cell (ref 0))
  (define-data Box (box (value I64 box-value)))
  (define-overload choose (-> I64 I64) (lambda (x) x)))''',
    'test/left.sfir': '''(library (test left)
  (export left)
  (import (rename (only (test shared) cell) (cell left))))''',
    'test/right.sfir': '''(library (test right)
  (export right)
  (import (rename (only (test shared) cell) (cell right))))''',
    'test/extension.sfir': '''(library (test extension)
  (export choose)
  (import (only (test shared) choose))
  (define-overload choose (-> Bool Bool) (lambda (x) x)))''',
    'test/cycle-a.sfir': '(library (test cycle-a) (import (test cycle-b)))',
    'test/cycle-b.sfir': '(library (test cycle-b) (import (test cycle-a)))',
    'test/wrong-name.sfir': '(library (test different))',
    'test/conflict.sfir': '(library (test conflict) (export cell) (define cell 0))',
}

PASS = {
    'scalar': ('(define increment (-> I64 I64) (lambda (x) (i64-add x 1)))\n(increment 41)', '42'),
    'inferred-polymorphism': ('(define identity (lambda (x) x))\n(begin (identity #t) (identity 42))', '42'),
    'declared-polymorphism': ('(define identity (All (T) (-> T T)) (lambda (x) x))\n(identity 42)', '42'),
    'local-polymorphism': ('(let ((identity (lambda (x) x))) (begin (identity #t) (identity 42)))', '42'),
    'let-outer-scope': ('(let ((x 1)) (let ((x 2) (y x)) (i64-add x y)))', '3'),
    'let-effects': ('''(define cell (ref 0))
(define stamp (lambda (x) (begin (ref-set! cell (i64-add (i64-mul (ref-get cell) 10) x)) x)))
(let ((left (stamp 1)) (right (stamp 2))) (ref-get cell))''', '12'),
    'call-effects': ('''(define cell (ref 0))
(define stamp (lambda (x) (begin (ref-set! cell (i64-add (i64-mul (ref-get cell) 10) x)) x)))
(define read-result (lambda (left right) (ref-get cell)))
(read-result (stamp 1) (stamp 2))''', '12'),
    'block-shadowing': ('''(define x 1)
(begin (define read-x (lambda () x)) (define x 42) (read-x))''', '42'),
    'recursive-block': ('''(begin
  (define even (lambda (n) (if (i64-eq n 0) #t (odd (i64-sub n 1)))))
  (define odd (lambda (n) (if (i64-eq n 0) #f (even (i64-sub n 1)))))
  (if (even 1000) 42 0))''', '42'),
    'forward-read': ('(begin (define x y) (define y 42) x)', 'trap'),
    'class': ('''(define-class (Identity T) (: identity (-> T T)))
(define-instance (Identity I64) (identity (lambda (value) value)))
(identity 42)''', '42'),
    'overload': ('''(define-overload select (-> I64 I64) (lambda (x) x))
(define-overload select (-> Bool Bool) (lambda (x) x))
(select 42)''', '42'),
    'overload-result': ('''(define-overload select (-> I64 I64) (lambda (x) x))
(define-overload select (-> I64 F64) i64->f64)
(ann (select 42) F64)''', '42'),
    'inferred-overload': ('''(define-overload select (lambda (x) (i64-add x 1)))
(define-overload select (lambda (x) (not x)))
(select 41)''', '42'),
    'data': ('''(define-data (Maybe T) (none) (some (value T)))
(match (some 42) ((none) 0) ((some value) value))''', '42'),
    'quoted-empty-list': ('(if (null? (ann (quote ()) (List I64))) 42 0)', '42'),
    'rest-arguments': ('(define first (lambda (head . tail) head))\n(first 42 1 2)', '42'),
    'reference-alias': ('(let ((a (ref 0))) (let ((b a)) (begin (ref-set! b 42) (ref-get a))))', '42'),
    'module-shared-initializer': ('''(import (test left) (test right))
(begin (ref-set! left 42) (ref-get right))''', '42'),
    'module-renamed-type': ('''(import (rename (only (test shared) Box box box-value) (Box Alias) (box wrap)))
(box-value (ann (wrap 42) Alias))''', '42'),
    'module-overload-extension': ('''(import (rename (only (test shared) choose) (choose original)) (test extension))
(if (original #t) (choose 42) 0)''', '42'),
    'module-prefix-and-except': ('''(import (prefix (except (test shared) cell choose) p:))
(p:box-value (p:box 42))''', '42'),
    'module-program': ('(library (test main) (import (sfir primitive)) (define answer 42) answer)', '42'),
}

FAIL = {
    'function-shorthand': ('(define (f x) x)\n(f 1)', 'expected an identifier'),
    'macro': ('(define-syntax identity (syntax-rules () ((_ x) x)))\n42', 'unsupported SFIR form'),
    'scheme-import': ('(import (scheme base))\n42', 'SFIR library not found'),
    'reader-quote': ("'()", 'cannot parse SFIR source'),
    'nonempty-list-literal': ('(car (quote (42 7)))', 'unsupported strict literal'),
    'named-let': ('(let loop ((x 0)) x)', 'wrong form arity'),
    'derived-cond': ('(cond (#t 42))', 'unsupported SFIR form'),
    'derived-and': ('(and #t #t)', 'unsupported SFIR form'),
    'multiple-lambda-body': ('((lambda (x) x x) 42)', 'wrong form arity'),
    'multiple-let-body': ('(let ((x 42)) x x)', 'wrong form arity'),
    'missing-else': ('(if #t 42)', 'wrong form arity'),
    'empty-block': ('(begin)', 'block requires a final expression'),
    'definition-only-block': ('(begin (define x 42))', 'block requires a final expression'),
    'declaration-only-block': ('(begin (define-class (C T) (: f (-> T T))))', 'block requires a final expression'),
    'detached-signature': ('(: answer I64)\n(define answer 42)\nanswer', 'declaration is not an expression'),
    'reserved-parameter': ('(lambda (if) if)', 'reserved SFIR keyword'),
    'duplicate-parameter': ('(lambda (x x) x)', 'duplicate binding'),
    'duplicate-let': ('(let ((x 1) (x 2)) x)', 'duplicate binding'),
    'immutable-binding': ('(define x 1)\n(set! x 2)\nx', 'unsupported SFIR form'),
    'unused-macro': ('(define unused (lambda () (when #t 42)))\n42', 'unsupported SFIR form'),
    'rigid-signature': ('(define bad (All (T) (-> T T)) (lambda (x) (i64-add x 1)))\n42', 'rigid'),
    'nonboolean-if': ('(if 1 42 0)', 'cannot unify'),
    'invariant-reference': ('(let ((cell (ref 42))) (ref-set! cell #t))', 'cannot unify'),
    'nested-all': ('(define bad (-> (All (T) (-> T T))) (lambda () (lambda (x) x)))\n42', 'unsupported strict type'),
    'module-empty-name': ('(library)', 'library requires a name'),
    'module-cycle': ('(import (test cycle-a))\n42', 'cyclic library import'),
    'module-name-mismatch': ('(import (test wrong-name))\n42', 'library name does not match import'),
    'module-conflict': ('(import (test shared) (test conflict))\n42', 'conflicting imported bindings'),
    'module-unknown-import': ('(import (only (test shared) missing))\n42', 'unknown import'),
    'module-keyword-alias': ('(import (rename (only (test shared) cell) (cell if)))\n42', 'reserved SFIR keyword'),
}
