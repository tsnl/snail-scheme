(define-library (control catch)
  (export
   first-signal
   all-signals)
  (import
   (snail core base)
   (snail core io)
   (control signal))
  (begin
    ;; The value signalled first, or 0 when the action finishes.
    (define (first-signal (action (Fn → Unit ! Signal output-port))) (→ I64) (! output-port)
      (handle Signal ((signal (lambda (value resume) (drop resume) value)))
        (action)
        0))

    ;; Every value signalled, resuming the action after each: the frames
    ;; the action saves belong to other libraries' modules.
    (define (all-signals (action (Fn → Unit ! Signal output-port))) (→ (List I64)) (! output-port)
      (handle Signal ((signal (lambda (value resume) (Cons value (resume (unit))))))
        (action)
        (Nil)))))
