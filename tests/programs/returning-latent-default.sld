(import
 (snail core base)
 (snail core io))

(effect Read-value
  ((read-value (Fn → I64 ! Fs))))

(define (main) (→ Unit) (! Fs Output-port)
  (handle Read-value ((read-value (lambda () 42)))
    (display (read-value)) (newline))
  (unit))
