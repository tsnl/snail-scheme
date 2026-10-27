(define-library (control signal)
  (export
   Signal
   signal)
  (import
   (snail-core base))
  (begin
    ;; A control operation declared in one library, handled in a second
    ;; and performed in a third.
    (effect Signal
      ((ctl signal (-> I64 Unit))))))
