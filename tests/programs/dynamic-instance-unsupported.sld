(import
 (snail core base)
 (snail core io)
 (gradual describe))

(: unknown Any)
(define unknown #t)
(handle dyn-cast
    ((conversion-failed (lambda (error)
                          (write-line (match (CastError-reason error)
                                        ((UnsupportedInstance) "unsupported instance")
                                        (_ "wrong reason")))
                          (write-line (string-join (CastError-expected error) ", ")))))
  (describe unknown)
  (unit))
