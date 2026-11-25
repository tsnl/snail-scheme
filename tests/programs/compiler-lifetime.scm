(import
 (snail core base)
 (snail core io)
 (snail shell compiler))

(extern collect! "snail.core.support" "snail:gc/collect" (Fn → Unit))
(extern live "snail.core.support" "snail:gc/live" (Fn → I32))

;; Each call drops the emitted module before measuring. Only the same
;; checked frontend and its caller remain live between emissions.
(define (emit (input Checked)) (→ Unit)
  (unless (> (string-length (● (checked->wat input) text)) 0) (panic "empty module")))

(define (after-emission (input Checked)) (→ I64)
  (emit input)
  (collect!)
  (i32->i64 (live)))

(define (main (fs Fs) (out OutputPort)) (→ Unit)
  (let* ((input (source->checked fs (list "src") "examples/fibonacci.scm"
                                 (lambda (loading forms) (panic "unexpected generator"))
                                 (Some (list "snail" "target" "node")) (Nil)))
         (first (after-emission input)) (next (after-emission input)))
    (unless (= first next)
      (panic (string-append "compiler retained bytes across emissions: " (show (- next first)))))
    (write-line out "a finished emission releases its module")))
