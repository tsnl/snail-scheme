(import
 (snail core base)
 (snail core io))

(effect Seed ((seed (Fn → I64))))
(effect Choose ((ctl choose (Fn → I64))))

;; Both empty-row spellings are closed, not effect-polymorphic.
(define (square (n I64)) (→ I64) (!) (* n n))
(define (memoize-pure (f (Fn A → B !))) (→ (Fn A → B)) (∀ (A B))
  (cache f))

(define (memoize-effects (f (Fn A → B ! e))) (→ (Fn A → B ! e)) (∀ (A B e))
  (unsafe-effectful-cache f))
(define (with-seed (n I64)) (→ I64) (! Seed) (+ n (seed)))

;; A handled control operation has no outward effect and cannot suspend its caller.
(define (choose-here (n I64)) (→ I64) (!)
  (handle Choose ((choose (lambda (resume) (resume n)))) (choose)))

(define (main) (→ Unit) (! output-port)
  (let ((memo (memoize-pure square)) (bounded (lru-cache 2 choose-here)))
    (write-line (show (memo 4)))
    (write-line (show (bounded 7)))
    (write-line (show (bounded 7))))
  (handle Seed ((seed (lambda () 10)))
    (let* ((wrap unsafe-effectful-cache)
           (memo (memoize-effects with-seed))
           (alias (wrap with-seed))
           (bounded (unsafe-effectful-lru-cache 1 with-seed)))
      (write-line (show (memo 1)))
      (write-line (show (alias 2)))
      (write-line (show (bounded 3)))
      (handle Seed ((seed (lambda () 20)))
        (write-line (show (memo 1)))
        (write-line (show (alias 2)))
        (write-line (show (bounded 3)))
        (write-line (show (bounded 4)))))))
