(define-library (control catch)
  (export
   first-signal
   all-signals)
  (import
   (snail core base)
   (control signal))
  (begin
    ;; The value signalled first, or 0 when the action finishes.
    (define (first-signal (action (Fn → Unit))) (→ I64)
      (with-prompt signalling
                   (lambda ()
                     (action)
                     0)
                   (lambda (value resume) value)))

    ;; Every value signalled, resuming the action after each: the frames
    ;; the action saves belong to other libraries.
    (define (all-signals (action (Fn → Unit))) (→ (List I64))
      (with-prompt signalling
                   (lambda ()
                     (action)
                     (Nil))
                   (lambda (value resume) (Cons value (resume (unit))))))))
