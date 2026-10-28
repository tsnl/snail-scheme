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
    (: first-signal (-> (-> Unit ! Signal console) I64 ! console))
    (define (first-signal action)
      (handle Signal ((signal (lambda (value resume) value)))
        (action)
        0))

    ;; Every value signalled, resuming the action after each: the frames
    ;; the action saves belong to other libraries' modules.
    (: all-signals (-> (-> Unit ! Signal console) (List I64) ! console))
    (define (all-signals action)
      (handle Signal ((signal (lambda (value resume) (Cons value (resume (unit))))))
        (action)
        (Nil)))))
