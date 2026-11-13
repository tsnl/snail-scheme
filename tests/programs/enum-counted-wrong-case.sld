(import
 (snail core base)
 (snail core io))

(enum Choice
  (Left ((value (Rc I64))))
  (Right ((value (Rc I64)))))

(define (main) (→ Unit) (! mut output-port)
  ;; Counted enums place the tag after their ownership header.
  (let ((right (Right (rc 2))))
    (write-line (show (rc-get (Right-value right))))
    (Left-value-replace! right (begin (write-line "incoming") (rc 4)))
    (unit)))
