(import
 (snail core base)
 (snail core io))

(effect ReadValue
  ((read-value (Fn → I64 ! fs))))

(define (main) (→ Unit) (! fs output-port)
  (handle ReadValue ((read-value (lambda () 42)))
    (display (read-value)) (newline))
  (unit))
