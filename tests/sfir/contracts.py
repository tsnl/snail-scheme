"""Authored SFIR examples; no Scheme expansion or source translation."""

MODULES = {
    'test/shared.sfir': '''(define-library (test shared)
  (export cell Box box box-value choose)
  (import (sfir primitive))
  (begin
(def cell (ref (ann 0 I64)))
  (def Box (datatype () (box (value I64 box-value))))
  (define-overload choose (-> I64 I64) (lambda (x) x))))''',
    'test/left.sfir': '''(define-library (test left)
  (export left)
  (import (rename (only (test shared) cell) (cell left))))''',
    'test/right.sfir': '''(define-library (test right)
  (export right)
  (import (rename (only (test shared) cell) (cell right))))''',
    'test/extension.sfir': '''(define-library (test extension)
  (export choose)
  (import (only (test shared) choose))
  (begin
(define-overload choose (-> Bool Bool) (lambda (x) x))))''',
    'test/cycle-a.sfir': '(define-library (test cycle-a) (import (test cycle-b)))',
    'test/cycle-b.sfir': '(define-library (test cycle-b) (import (test cycle-a)))',
    'test/wrong-name.sfir': '(define-library (test different))',
    'test/conflict.sfir': '''(define-library (test conflict) (export cell) (begin
(def cell 0)))''',
}

PASS = {
    'scalar': ('''(def increment (-> I64 I64) (lambda (x) (i64-add x (ann 1 I64))))
(increment (ann 41 I64))''', '42'),
    'inferred-polymorphism': ('''(def identity (lambda (x) x))
(begin (identity #t) (identity (ann 42 I64)))''', '42'),
    'declared-polymorphism': ('''(def identity (All (T) (-> T T)) (lambda (x) x))
(identity (ann 42 I64))''', '42'),
    'local-polymorphism': ('(begin (let identity (lambda (x) x)) (begin (identity #t) (identity (ann 42 I64))))', '42'),
    'let-outer-scope': ('''(begin (let x (ann 1 I64)) (begin (let sfir-migration-let-1 (ann 2 I64)) (let sfir-migration-let-2 x) (let x sfir-migration-let-1)
(let y sfir-migration-let-2)
(i64-add x y)))''', '3'),
    'let-effects': ('''(def cell (ref (ann 0 I64)))
(def stamp (lambda (x) (begin (ref-set! cell (i64-add (i64-mul (ref-get cell) (ann 10 I64)) x)) x)))
(begin (let sfir-migration-let-1 (stamp (ann 1 I64))) (let sfir-migration-let-2 (stamp (ann 2 I64))) (let left sfir-migration-let-1)
(let right sfir-migration-let-2)
(ref-get cell))''', '12'),
    'call-effects': ('''(def cell (ref (ann 0 I64)))
(def stamp (lambda (x) (begin (ref-set! cell (i64-add (i64-mul (ref-get cell) (ann 10 I64)) x)) x)))
(def read-result (lambda (left right) (ref-get cell)))
(read-result (stamp (ann 1 I64)) (stamp (ann 2 I64)))''', '12'),
    'block-shadowing': ('''(def x (ann 1 I64))
(begin (def read-x (lambda () x)) (def x (ann 42 I64)) (read-x))''', '42'),
    'recursive-block': ('''(begin
  (def even (lambda (n) (if (i64-eq n (ann 0 I64)) #t (odd (i64-sub n (ann 1 I64))))))
  (def odd (lambda (n) (if (i64-eq n (ann 0 I64)) #f (even (i64-sub n (ann 1 I64))))))
  (if (even (ann 1000 I64)) (ann 42 I64) (ann 0 I64)))''', '42'),
    'forward-read': ('(begin (def x y) (def y (ann 42 I64)) x)', 'trap'),
    'class': ('''(def Identity (typeclass ( T) (: identity (-> T T))))
(def sfir-migration-instance-1 (instance (Identity I64) (identity (lambda (value) value))))
(identity (ann 42 I64))''', '42'),
    'overload': ('''(define-overload select (-> I64 I64) (lambda (x) x))
(define-overload select (-> Bool Bool) (lambda (x) x))
(select (ann 42 I64))''', '42'),
    'overload-result': ('''(define-overload select (-> I64 I64) (lambda (x) x))
(define-overload select (-> I64 F64) i64->f64)
(ann (select (ann 42 I64)) F64)''', '42'),
    'inferred-overload': ('''(define-overload select (lambda (x) (i64-add x (ann 1 I64))))
(define-overload select (lambda (x) (not x)))
(select (ann 41 I64))''', '42'),
    'data': ('''(def Maybe (datatype ( T) (none) (some (value T))))
(match (some (ann 42 I64)) ((none) (ann 0 I64)) ((some value) value))''', '42'),
    'empty-list-operation': ('(if (null? (ann (empty-list) (List I64))) (ann 42 I64) (ann 0 I64))', '42'),
    'rest-arguments': ('''(def first (lambda (head . tail) head))
(first (ann 42 I64) (ann 1 I64) (ann 2 I64))''', '42'),
    'reference-alias': ('(begin (let a (ref (ann 0 I64))) (begin (let b a) (begin (ref-set! b (ann 42 I64)) (ref-get a))))', '42'),
    'module-shared-initializer': ('''(import (test left) (test right))
(begin (ref-set! left (ann 42 I64)) (ref-get right))''', '42'),
    'module-renamed-type': ('''(import (rename (only (test shared) Box box box-value) (Box Alias) (box wrap)))
(box-value (ann (wrap (ann 42 I64)) Alias))''', '42'),
    'module-overload-extension': ('''(import (rename (only (test shared) choose) (choose original)) (test extension))
(if (original #t) (choose (ann 42 I64)) (ann 0 I64))''', '42'),
    'module-selected-renames': ('''(import (rename (only (test shared) Box box box-value)
  (Box p:Box) (box p:box) (box-value p:box-value)))
(p:box-value (p:box (ann 42 I64)))''', '42'),
    'module-program': ('''(define-library (test main) (import (sfir primitive)) (begin
(def answer (ann 42 I64)) answer))''', '42'),
    'sequential-shadow-and-capture': ('''(begin
  (let value (ann 40 I64))
  (def read-value (-> I64) (lambda () value))
  (let value (i64-add value (ann 2 I64)))
  (i64-add (read-value) value))''', '82'),
    'separate-type-and-value-names': ('''(def keep (All (T) (-> T T))
  (lambda (T) (ann T T)))
(keep (ann 42 I64))''', '42'),
    'nested-all-and-outer-annotation': ('''(def keep (All (T) (-> T T))
  (lambda (T)
    (begin
      (def identity (All (T) (-> T T)) (lambda (value) (ann value T)))
      (identity #t)
      (ann T T))))
(keep (ann 42 I64))''', '42'),
    'library-concatenated-clauses': ('''(define-library (test clauses)
  (import (sfir primitive))
  (export answer)
  (begin (let first (ann 20 I64)))
  (begin (def answer (-> I64) (lambda () (i64-add first (ann 22 I64)))) (answer)))''', '42'),
    'named-instance-kind': ('''(def Identity (Kind-> Type Constraint)
  (typeclass (T) (: identity (-> T T))))
(def identity-i64 (Evidence (Identity I64))
  (instance (Identity I64) (identity (lambda (value) value))))
(identity (ann 42 I64))''', '42'),
    'empty-list-any-roundtrip': ('''(def saved Any (ann (empty-list) (List I64)))
(if (null? (ann saved (List I64))) (ann 42 I64) (ann 0 I64))''', '42'),
    'let-polymorphic-alias': ('''(begin
  (let initial-identity (lambda (value) value))
  (let initial-number (ann 42 I64))
  (let identity initial-identity)
  (let number initial-number)
  (identity #t)
  (identity number))''', '42'),
    'captured-monotype-immediate': ('''(import (only (sfir base) <))
((lambda (length)
   (begin
     (def smaller (-> I64 Bool) (lambda (value) (< value length)))
     (if (smaller (ann 1 I64)) (ann 42 I64) (ann 0 I64))))
 (ann 2 I64))''', '42'),
    'captured-monotype-named': ('''(import (only (sfir base) <))
(def outer
  (lambda (length)
    (begin
      (def smaller (-> I64 Bool) (lambda (value) (< value length)))
      (if (smaller (ann 1 I64)) (ann 42 I64) (ann 0 I64)))))
(outer (ann 2 I64))''', '42'),
    'captured-monotype-late-body': ('''(import (only (sfir base) <))
((lambda (length)
   (begin
     (def smaller (-> I64 Bool) (lambda (value) (< value length)))
     (i64-add length (ann 0 I64))
     (if (smaller (ann 1 I64)) (ann 42 I64) (ann 0 I64))))
 (ann 2 I64))''', '42'),
    'captured-monotype-unused-body': ('''(import (only (sfir base) <))
((lambda (length)
   (begin
     (def smaller (-> I64 Bool) (lambda (value) (< value length)))
     (ann 42 I64)))
 (ann 2 I64))''', '42'),
    'captured-monotype-unused-generic': ('''(define-library (test captured)
  (export make-smaller)
  (import (sfir base))
  (begin
    (def make-smaller
      (lambda (length)
        (begin
          (def smaller (-> I64 Bool) (lambda (value) (< value length)))
          smaller)))
    (ann 42 I64)))''', '42'),
    'captured-monotype-mixed-quantifier': ('''(define-overload compatible
  (All (T) (-> I64 T Bool)) (lambda (number value) #t))
(define-overload compatible (-> Bool Bool Bool) (lambda (left right) #f))
((lambda (outer)
   (begin
     (def inner (All (A) (-> A Bool))
       (lambda (value) (compatible outer value)))
     (if (inner #t) (ann 42 I64) (ann 0 I64))))
 (ann 2 I64))''', '42'),
}

FAIL = {
    'function-shorthand': ('''(def (f x) x)
(f 1)''', 'expected an identifier'),
    'macro': ('(define-syntax identity (syntax-rules () ((_ x) x)))\n42', 'unsupported SFIR form'),
    'scheme-import': ('(import (scheme base))\n42', 'SFIR library not found'),
    'reader-quote': ("'()", 'cannot parse SFIR source'),
    'nonempty-list-literal': ('(car (quote (42 7)))', 'unsupported SFIR form'),
    'named-let': ('(let loop ((x 0)) x)', 'nominal application requires type arguments'),
    'derived-cond': ('(cond (#t 42))', 'unsupported SFIR form'),
    'derived-and': ('(and #t #t)', 'unsupported SFIR form'),
    'multiple-lambda-body': ('((lambda (x) x x) 42)', 'wrong form arity'),
    'multiple-let-body': ('(let ((x 42)) x x)', 'expected an identifier'),
    'missing-else': ('(if #t 42)', 'wrong form arity'),
    'empty-block': ('(begin)', 'block requires a final expression'),
    'definition-only-block': ('(begin (def x 42))', 'block requires a final expression'),
    'declaration-only-block': ('(begin (def C (typeclass ( T) (: f (-> T T)))))', 'static definitions require library scope'),
    'detached-signature': ('''(: answer I64)
(def answer 42)
answer''', 'declaration is not an expression'),
    'reserved-parameter': ('(lambda (if) if)', 'reserved SFIR keyword'),
    'duplicate-parameter': ('(lambda (x x) x)', 'duplicate binding'),
    'legacy-duplicate-let': ('(let ((x 1) (x 2)) x)', 'expected an identifier'),
    'immutable-binding': ('''(def x 1)
(set! x 2)
x''', 'unsupported SFIR form'),
    'unused-macro': ('''(def unused (lambda () (when #t 42)))
42''', 'unsupported SFIR form'),
    'rigid-signature': ('''(def bad (All (T) (-> T T)) (lambda (x) (i64-add x 1)))
42''', 'rigid'),
    'nonboolean-if': ('(if (ann 1 I64) 42 0)', 'cannot unify'),
    'invariant-reference': ('(begin (let cell (ref (ann 42 I64))) (ref-set! cell #t))', 'cannot unify'),
    'nested-all': ('''(def bad (-> (All (T) (-> T T))) (lambda () (lambda (x) x)))
42''', 'All and constraints belong to an attached binding signature'),
    'module-empty-name': ('(define-library)', 'library requires a name'),
    'module-cycle': ('(import (test cycle-a))\n42', 'cyclic library import'),
    'module-name-mismatch': ('(import (test wrong-name))\n42', 'library name does not match import'),
    'module-conflict': ('(import (test shared) (test conflict))\n42', 'conflicting imported bindings'),
    'module-unknown-import': ('(import (only (test shared) missing))\n42', 'unknown import'),
    'module-keyword-alias': ('(import (rename (only (test shared) cell) (cell if)))\n42', 'reserved SFIR keyword'),
    'def-let-name-conflict': ('(begin (def value 1) (let value 2) value)', 'let conflicts'),
    'local-datatype': ('(begin (def Local (datatype () (local))) (unit))', 'static definitions require library scope'),
    'wrong-static-kind': ('(def Flag Constraint (datatype () (off) (on)))\n42', 'kind mismatch'),
    'evidence-is-not-a-value': ('''(def Identity (typeclass (T) (: identity (-> T T))))
(def identity-i64 (instance (Identity I64) (identity (lambda (value) value))))
identity-i64''', 'static definition is not a value'),
    'let-application-alias-is-monomorphic': ('''(def make-identity (lambda () (lambda (value) value)))
(begin
  (let initial-identity (make-identity))
  (let initial-number (ann 42 I64))
  (let identity initial-identity)
  (let number initial-number)
  (identity #t)
  (identity number))''', 'cannot unify'),
    'legacy-define': ('(define answer 42)\nanswer', 'unsupported SFIR form'),
    'legacy-library': ('(library (old))', 'unsupported SFIR form'),
    'legacy-data': ('(define-data Flag (off) (on))\n42', 'unsupported SFIR form'),
    'legacy-empty-quote': ('(quote ())', 'unsupported SFIR form'),
    'legacy-top': ('(ann 42 Top)', 'Top'),
    'legacy-prefix': ('(import (prefix (test shared) p:))\n42', 'unsupported SFIR import modifier'),
    'legacy-except': ('(import (except (test shared) cell))\n42', 'unsupported SFIR import modifier'),
    'captured-monotype-wrong-argument': ('''(import (only (sfir base) <))
((lambda (length)
   (begin
     (def smaller (-> I64 Bool) (lambda (value) (< value length)))
     (smaller (ann 1 I64))))
 #t)''', 'no compatible overload signature'),
    'captured-monotype-missing-all': ('''(import (only (sfir base) <))
(def compare (All (A) (-> A A Bool)) (lambda (left right) (< left right)))
(ann 42 I64)''', 'typeclass obligation is absent from declared constraints'),
    'captured-monotype-mixed-missing': ('''(define-overload compatible
  (-> I64 I64 Bool) (lambda (number value) #t))
(define-overload compatible (-> Bool Bool Bool) (lambda (left right) #f))
((lambda (outer)
   (begin
     (def inner (All (A) (-> A Bool))
       (lambda (value) (compatible outer value)))
     (ann 42 I64)))
 (ann 2 I64))''', 'typeclass obligation is absent from declared constraints'),
    'captured-monotype-private-obligation': ('''(define-overload choose
  (-> I64) (lambda () (ann 1 I64)))
(define-overload choose (-> F64) (lambda () (ann 1.0 F64)))
(def unused (-> Bool)
  (lambda () (begin (let private (choose)) #t)))
(ann 42 I64)''', 'typeclass obligation is absent from declared constraints'),
    'captured-monotype-late-skolem-escape': ('''(define-overload choose
  (All (T) (-> I64 T T)) (lambda (number value) value))
(define-overload choose
  (All (T) (-> Bool T T)) (lambda (boolean value) value))
(def make
  (lambda (length captured)
    (begin
      (def inner (All (A) (-> A A)) (lambda (unused) (choose length captured)))
      (i64-add length (ann 0 I64))
      inner)))
(ann 42 I64)''', 'rigid type escapes its declaration'),
}
