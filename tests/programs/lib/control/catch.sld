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
    (define (first-signal (action (Fn → Unit ! Signal Output-port))) (→ I64) (! Output-port)
      (handle Signal ((signal (lambda (value resume) value)))
        (action)
        0))

    ;; Every value signalled, resuming the action after each: the frames
    ;; the action saves belong to other libraries' modules.
    (define (all-signals (action (Fn → Unit ! Signal Output-port))) (→ (List I64)) (! Output-port)
      (handle Signal ((signal (lambda (value resume) (Cons value (resume (unit))))))
        (action)
        (Nil)))))
