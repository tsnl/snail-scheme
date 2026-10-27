(define-library (control catch)
  (export
   first-signal)
  (import
   (snail-core base)
   (snail-core io)
   (control signal))
  (begin
    ;; The value signalled first, or 0 when the action finishes.
    (: first-signal (-> (-> Unit ! Signal console) I64 ! console))
    (define (first-signal action)
      (handle Signal ((signal (lambda (value resume) value)))
        (action)
        0))))
