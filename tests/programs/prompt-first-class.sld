(import
 (snail core base)
 (snail core io))

(define asking (→ (Prompt I64 I64)) (make-prompt))

(define telling (→ (Prompt String Unit)) (make-prompt))

(define (run (delimit (Fn (Prompt I64 I64) (Fn → I64) (Fn I64 (Fn I64 → I64) → I64) → I64)))
  (→ I64)
  (delimit asking
           (lambda ()
             (let ((n (suspend asking 1)))
               (suspend telling "inside")
               (+ n 1)))
           (lambda (n resume) (+ 100 (resume (* n 10))))))

(define (main (out OutputPort)) (→ Unit)
  (display out
           (with-prompt telling
                        (lambda () (run with-prompt))
                        (lambda (line resume)
                          (write-line out line)
                          (resume (unit)))))
  (newline out)
  (unit))
