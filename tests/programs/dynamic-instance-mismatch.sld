(import
 (snail core base)
 (snail core io))

(instance (Num (! dyn-cast) Any)
  (dispatch I64 F64))

(define left (→ Any) 1)

(define right (→ Any) 2.0)

(define (main) (→ Unit) (! output-port)
  (handle dyn-cast
      ((conversion-failed (lambda (error)
                            (write-line (match (● error reason)
                                          ((ArgumentMismatch) "argument mismatch")
                                          (_ "wrong reason")))
                            (write-line (string-join (● error expected) ", "))
                            (display (● error argument))
                            (newline))))
    (+ left right)
    (unit))
  (unit))
