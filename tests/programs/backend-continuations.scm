(import (scheme base) (scheme write) (scheme process-context) (snail-scheme runtime))

;; These checks cover control state and the shared Scheme store. Parameterization
;; across nonlocal exits requires dynamic-wind, which is not implemented yet.

;; ---- Assertions and stack growth ----

(define (check expected actual)
  (if (not (equal? expected actual)) (error "continuation mismatch" expected actual)))

(define (deep-call depth thunk)
  (if (= depth 0) (thunk) (+ 1 (deep-call (- depth 1) thunk))))

(define (capture-add receiver)
  (+ 10 (call-with-current-continuation receiver)))

;; ---- Repeated invocation and mutation ----

(define (multi-shot)
  (let ((saved #f) (step 0) (seen '()))
    (let ((value (capture-add (lambda (k) (set! saved k) 1))))
      (set! seen (cons value seen))
      (set! step (+ step 1))
      (if (< step 3) (saved (+ step 1)) (reverse seen)))))

;; count is assigned but never mentioned by an ordinary nested lambda.
(define (uncaptured-mutation)
  (let ((saved #f) (count 0))
    (call/cc (lambda (k) (set! saved k) #f))
    (set! count (+ count 1))
    (if (< count 3) (saved #f) count)))

(define (closure-created-after-capture)
  (let ((saved #f) (reader #f) (value 1))
    (call/cc (lambda (k) (set! saved k) #f))
    (if reader (reader)
        (begin (set! reader (lambda () value))
               (set! value 9)
               (saved #f)))))

(define (heap-mutation)
  (let ((saved #f) (pair (cons 0 '())))
    (call/cc (lambda (k) (set! saved k) #f))
    (set-car! pair (+ 1 (car pair)))
    (if (< (car pair) 3) (saved #f) (car pair))))

(define global-count 0)

(define (global-mutation)
  (let ((saved #f))
    (call/cc (lambda (k) (set! saved k) #f))
    (set! global-count (+ global-count 1))
    (if (< global-count 3) (saved #f) global-count)))

;; ---- Multiple values and nested control ----

(define (multiple-shot-values)
  (let ((saved #f) (step 0) (seen '()))
    (let ((received
           (call-with-values
               (lambda () (call/cc (lambda (k) (set! saved k) (values 1 2))))
             list)))
      (set! seen (cons received seen))
      (set! step (+ step 1))
      (cond ((= step 1) (saved))
            ((= step 2) (apply saved '(3 4 5)))
            (else (reverse seen))))))

(define (nested-escape)
  (+ 1 (call/cc
        (lambda (outer)
          (+ 100 (call/cc (lambda (inner) (outer (inner 7)))))))))

;; ---- Snapshot roots and relocation ----

(define (saved-local receiver)
  (let ((pair (cons 'retained '())))
    (call/cc receiver)
    (car pair)))

(define (snapshot-roots)
  (let ((saved #f) (step 0))
    (let ((value (saved-local (lambda (k) (set! saved k) #f))))
      (set! step (+ step 1))
      (if (= step 1)
          (begin (collect-garbage) (saved #f))
          value))))

(define (immutable-reader)
  (let ((value (cons 'immutable '()))) (lambda () value)))

(define (immutable-capture)
  (let ((read (immutable-reader)))
    (collect-garbage)
    (car (read))))

;; Pending arguments belong to the snapshot too. Restore them twice after a
;; larger stack growth, which must preserve the meaning of saved stack offsets.
(define (pending-argument receiver)
  (list (cons 'pending '()) (deep-call 40 (lambda () (call/cc receiver)))))

(define (grown-snapshot)
  (let ((saved #f) (step 0) (seen '()))
    (let ((result (pending-argument (lambda (k) (set! saved k) 0))))
      (check 'pending (car (car result)))
      (set! seen (cons (cadr result) seen))
      (set! step (+ step 1))
      (if (< step 3)
          (begin (deep-call 2000 (lambda () 0))
                 (collect-garbage)
                 (saved step))
          (reverse seen)))))

;; ---- Tail calls with changing argument counts ----

(define (narrow-tail n a)
  (if (= n 0) a (wide-tail (- n 1) a 2 3 4 5)))

(define (wide-tail n a b c d e)
  (narrow-tail n (+ a b c d e)))

;; ---- Tests ----

(define (successful-cases)
  (check 7 (call/cc (lambda (escape) (+ 100 (escape 7)))))
  (check 8 (call-with-current-continuation (lambda (unused) 8)))
  (check #t (call/cc procedure?))
  (check 9 (call/cc (lambda (escape) (apply escape '(9)))))
  (check '(11 12 13) (multi-shot))
  (check 3 (uncaptured-mutation))
  (check 9 (closure-created-after-capture))
  (check 3 (heap-mutation))
  (check 3 (global-mutation))
  (check '((1 2) () (3 4 5)) (multiple-shot-values))
  (check 108 (nested-escape))
  (check 'retained (snapshot-roots))
  (check 'immutable (immutable-capture))
  (check '((a) #(b))
         (call-with-values
             (lambda () (call/cc (lambda (k) (k (cons 'a '()) (vector 'b)))))
           list))
  (check '(40 41 42) (grown-snapshot))
  (check 140000 (narrow-tail 10000 0))
  (display "continuation checks passed\n"))

(define (invalid-case mode)
  (case (string->symbol mode)
    ((empty-result) (cons (call/cc (lambda (k) (k))) '()))
    ((many-results) (cons (call/cc (lambda (k) (k 1 2))) '()))
    ((callcc-arity) (call/cc))
    (else (error "unknown continuation test" mode))))

(if (null? (cdr (command-line)))
    (successful-cases)
    (invalid-case (cadr (command-line))))
