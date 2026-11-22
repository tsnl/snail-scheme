(import
 (snail core base)
 (snail core io))

(effect ReadValue
  ((read-value (Fn → I64 ! mut))))

(define (main (fs Fs) (out OutputPort)) (→ Unit) (! mut)
  (handle ReadValue ((read-value (lambda () 42)))
    (display out (read-value fs)) (newline out))
  (unit))
