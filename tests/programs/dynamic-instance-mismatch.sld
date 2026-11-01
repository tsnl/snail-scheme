(import
 (snail core base)
 (snail core io))

(instance (Num (! dyn-tc) Any)
  (dispatch I64 F64))

(: left Any)
(define left 1)
(: right Any)
(define right 2.0)
(handle dyn-tc
    ((conversion-failed (lambda (error)
                          (write-line (match (CastError-reason error)
                                        ((ArgumentMismatch) "argument mismatch")
                                        (_ "wrong reason")))
                          (write-line (string-join (CastError-expected error) ", "))
                          (display (CastError-argument error))
                          (newline))))
  (+ left right)
  (unit))
