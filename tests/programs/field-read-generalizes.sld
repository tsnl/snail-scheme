(import
 (snail core base)
 (snail core io))

(record (Box T)
  ((value T)))

;; The match says what b is, so the read resolves where it is written and
;; leaves contents generic: (Box t) → t.
(define contents
  (lambda (b)
    (match b
      ((Box _) (● b value)))))

(define (main) (→ Unit) (! output-port)
  (write-line (show (contents (new Box (value 1)))))
  (write-line (contents (new Box (value "two")))))
