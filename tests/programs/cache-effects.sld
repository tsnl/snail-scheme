(import
 (snail core base)
 (snail core io))

;; How often a function ran, which a cache's hits leave alone.
(record Count
  ((value I64)))

(define asking (→ (Prompt Unit I64)) (make-prompt))

;; Both empty-row spellings are closed, not effect-polymorphic.
(define (square (n I64)) (→ I64) (!) (* n n))

(define (memoize-pure (f (Fn A → B !))) (→ (Fn A → B)) (∀ (A B))
  (cache f))

(define (memoize-effects (f (Fn A → B ! e))) (→ (Fn A → B ! e)) (∀ (A B e))
  (cache f))

;; A suspension its own `with-prompt` catches never leaves the function.
(define (ask-here (n I64)) (→ I64)
  (with-prompt asking (lambda () (suspend asking (unit))) (lambda (value resume) (resume n))))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (let ((memo (memoize-pure square)) (bounded (lru-cache 2 ask-here)))
    (write-line out (show (memo 4)))
    (write-line out (show (bounded 7)))
    (write-line out (show (bounded 7))))
  (let* ((count (new Count (value 10)))
         (counting (lambda (n)
                     (set! (● count value) (+ (● count value) 1))
                     (+ n (● count value))))
         (wrap cache)
         (memo (memoize-effects counting))
         (alias (wrap counting))
         (bounded (lru-cache 1 counting)))
    ;; Each cache runs the function once for each key it has not kept.
    (write-line out (show (memo 1)))
    (write-line out (show (alias 2)))
    (write-line out (show (bounded 3)))
    (write-line out (show (memo 1)))
    (write-line out (show (alias 2)))
    (write-line out (show (bounded 3)))
    (write-line out (show (bounded 4)))
    (write-line out (show (bounded 3)))
    (write-line out (show (● count value)))))
