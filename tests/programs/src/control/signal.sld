(define-library (control signal)
  (export
   signalling
   signal)
  (import
   (snail core base))
  (begin
    ;; A prompt made in one library, caught in a second and suspended to in
    ;; a third.
    (define signalling (→ (Prompt I64 Unit)) (make-prompt))

    (define (signal (value I64)) (→ Unit)
      (suspend signalling value))))
