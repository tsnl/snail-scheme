;; Canonical bare Lofi. See migration.json for source provenance.

(import (lofi base))

(def cddr (lambda (xs.2) (cdr (cdr xs.2))))

(def length
  (lambda (xs)
    (((lambda () (begin (def loop.6 (lambda (xs.1 n.12) (if (null? xs.1) n.12 (loop.6 (cdr xs.1) (+ n.12 (ann 1 I64)))))) loop.6)))
      xs
      (ann 0 I64))))

(define-extern native-input-i64 "benchmark" "input_i64" (-> I32 I64))

(define-extern native-input-f64 "benchmark" "input_f64" (-> I32 F64))

(define-extern barrier "benchmark" "barrier" (-> Bool))

(define-extern hide-i64 "benchmark" "hide_i64" (-> I64 I64))

(define-extern hide-f64 "benchmark" "hide_f64" (-> F64 F64))

(def integer-zero? (lambda (n.11) (= n.11 (ann 0 I64))))

(def integer-positive? (lambda (n.10) (> n.10 (ann 0 I64))))

(def integer-max (lambda (a b) (if (> a b) a b)))

(def nonempty-list? (lambda (value.1) (not (null? value.1))))

(def equal-permutation?
  (lambda (left right)
    (if (null? left)
      (null? right)
      (if (not (null? right))
        (if (= (car left) (car right)) (equal-permutation? (cdr left) (cdr right)) #f)
        #f))))

(def PermutationPlan (datatype ()
  (make-permutation-plan
    (work (-> (Vector (List (List I64)))) permutation-work)
    (accept (-> (Vector (List (List I64))) Bool) permutation-accept))))

(def run-benchmark-x
  (lambda (m.1 n.9 k.1 ell.1 thunk accept.1) (make-permutation-plan thunk accept.1)))

(def hide (lambda (count.1 x.6) (hide-i64 x.6)))

(def permutations
  (lambda (x.2)
    ((lambda (x.3 perms) (begin (def P (lambda (n.8) (if (> n.8 (ann 1 I64)) (begin (((lambda () (begin (def loop.5 (lambda (j.2) (if (integer-zero? j.2) (P (- n.8 (ann 1 I64))) (begin (P (- n.8 (ann 1 I64))) (F n.8) (loop.5 (- j.2 (ann 1 I64))))))) loop.5))) (- n.8 (ann 1 I64))) (unit)) (unit)))) (def F (lambda (n.7) (begin (ref-set! x.3 (revloop (ref-get x.3) n.7 (list-tail (ref-get x.3) n.7))) (ref-set! perms (cons (ref-get x.3) (ref-get perms)))))) (def revloop (lambda (x.5 n.6 y.1) (if (integer-zero? n.6) y.1 (revloop (cdr x.5) (- n.6 (ann 1 I64)) (cons (car x.5) y.1))))) (def list-tail (lambda (x.4 n.5) (if (integer-zero? n.5) x.4 (list-tail (cdr x.4) (- n.5 (ann 1 I64)))))) (P (length (ref-get x.3))) (ref-get perms)))
      (ref x.2)
      (ref (cons x.2 (empty-list ))))))

(def sumlists
  (lambda (x)
    (((lambda () (begin (def loop.3 (lambda (x.1 sum) (if (null? x.1) sum (loop.3 (cdr x.1) (((lambda () (begin (def loop.4 (lambda (y sum.1) (if (null? y) sum.1 (loop.4 (cdr y) (+ sum.1 (car y)))))) loop.4))) (car x.1) sum))))) loop.3)))
      x
      (ann 0 I64))))

(def one..n
  (lambda (n.3)
    (((lambda () (begin (def loop.2 (lambda (n.4 p) (if (integer-zero? n.4) p (loop.2 (- n.4 (ann 1 I64)) (cons n.4 p))))) loop.2)))
      n.3
      (empty-list ))))

(def tenperm
  (lambda rest ((lambda (n.2) (MpermNKL-benchmark (ann 10 I64) n.2 (ann 2 I64) (ann 1 I64))) (if (null? rest) (ann 9 I64) (car rest)))))

(def MpermNKL-benchmark
  (lambda (m n k ell)
    (if (if (<= (ann 0 I64) m) (if (integer-positive? n) (if (integer-positive? k) (if (<= (ann 0 I64) ell) (<= ell k) #f) #f) #f) #f)
      ((lambda (queue) (begin (def fill-queue (lambda (i.2 j.1) (if (< i.2 j.1) (begin (vector-set! queue i.2 (permutations (one..n n))) (fill-queue (+ i.2 (ann 1 I64)) j.1) (unit)) (unit)))) (def flush-queue (lambda () (((lambda () (begin (def loop.1 (lambda (i.1) (if (< i.1 k) (begin (vector-set! queue i.1 ((lambda (j) (if (< j k) (vector-ref queue j) (empty-list ))) (+ i.1 ell))) (loop.1 (+ i.1 (ann 1 I64))) (unit)) (unit)))) loop.1))) (ann 0 I64)))) (fill-queue (ann 0 I64) (- k ell)) (run-benchmark-x m n k ell (lambda () (begin (fill-queue (- k ell) k) (flush-queue) queue)) (lambda (q) (begin (def factorial (lambda (n.1) (if (= n.1 (ann 0 I64)) (ann 1 I64) (* n.1 (factorial (- n.1 (ann 1 I64))))))) ((lambda (q0 qi) (if ((lambda (value) (if value value (if (nonempty-list? q0) (if (nonempty-list? qi) (equal-permutation? (car q0) (car qi)) #f) #f))) (if (null? q0) (null? qi) #f)) (= (sumlists q0) (quotient (* (* n (+ n (ann 1 I64))) (factorial n)) (ann 2 I64))) #f)) (vector-ref q (ann 0 I64)) (vector-ref q (integer-max (ann 0 I64) (- (- k ell) (ann 1 I64))))))))))
        (make-vector k (empty-list )))
      (unreachable))))

(define-extern native-count "benchmark" "count" (-> I64))

(def setup-count (native-count))

(def setup-m (hide setup-count setup-count))

(def input0 (hide setup-count (native-input-i64 (ann 0 I32))))

(def input1 (hide setup-count (native-input-i64 (ann 1 I32))))

(def input2 (hide setup-count (native-input-i64 (ann 2 I32))))

(def plan (MpermNKL-benchmark setup-m input0 input1 input2))

(def bench (-> I64 I64)
  (lambda (count)
    ((lambda (work accept) (if (accept (((lambda () (begin (def loop (lambda (i result) (if (< i count) (loop (+ i (ann 1 I64)) (work)) result))) loop))) (ann 0 I64) (ann (empty-vector) (Vector (List (List I64)))))) (ann 1 I64) (ann 0 I64)))
      (permutation-work plan)
      (permutation-accept plan))))

(unit)
