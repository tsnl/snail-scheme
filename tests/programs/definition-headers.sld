;; Header variables scope over parameter types and body annotations. Class
;; evidence and callable ownership retain the same checking obligations.
(import
 (snail core base)
 (snail core io))

(define (twice (value T))
  (→ T)
  (! E)
  (∀ T E)
  (⊨ (Num E T) (Copy T))
  (annotations (doc "Add a value to itself."))
  (+ (ann value T) value))

(define empty
  (→ (List T))
  (∀ T)
  (Nil))

(define (apply-one (action (impl (FnOnce I64 → I64))) (value I64))
  (→ I64)
  (action value))

(define (offset (amount I64))
  (→ I64)
  (define (add-offset (value I64))
    (→ I64)
    (+ amount value))
  (define (countdown (value I64))
    (→ I64)
    (if (= value 0) 36 (countdown (- value 1))))
  (define (boxed-countdown (value I64))
    (→ Any)
    (if (= value 0) "done" (boxed-countdown (- value 1))))
  (add-offset
   (match (try-convert (boxed-countdown 2) String)
     ((Ok _) (countdown 3))
     ((Err _) 0))))

(define (answer)
  (→ I64)
  42)

(write-line (i64->string (twice 21)))
(write-line (i64->string (length (ann empty (List I64)))))
(write-line (i64->string (apply-one (lambda (value) (+ value 1)) 41)))
(write-line (i64->string (offset 7)))
(write-line (i64->string (answer)))
