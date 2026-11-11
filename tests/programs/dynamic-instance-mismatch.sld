(import
 (snail core base)
 (snail core io))

(instance (Num (! dyn-cast) Any)
  (dispatch I64 F64))

(define left (→ Any) 1)
(define right (→ Any) 2.0)
(handle dyn-cast
    ((conversion-failed (lambda (error)
                          (write-line (match (::reason error)
                                        ((ArgumentMismatch) "argument mismatch")
                                        (_ "wrong reason")))
                          (write-line (string-join (::expected error) ", "))
                          (display (::argument error))
                          (newline))))
  (+ left right)
  (unit))
