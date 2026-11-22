(import
 (snail core base)
 (snail core io))

(define failing (→ (Prompt String Never)) (make-prompt))

;; `make` is array-generate, handed over as a value.
(define (build (out OutputPort) (make (Fn I64 (Fn I64 → I64) → (Array I64)))) (→ I64)
  (let ((items (make 3 (lambda (i) (if (= i 1) (absurd (suspend failing "element 1")) i)))))
    (write-line out "after the array: this line must not print")
    (array-length items)))

(define (main (out OutputPort)) (→ Unit)
  (write-line out
              (with-prompt failing
                           (lambda () (show (build out array-generate)))
                           (lambda (why resume) (string-append "failed: " why))))
  (unit))
