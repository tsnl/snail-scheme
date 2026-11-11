(import
 (snail core base)
 (snail core io)
 (gradual describe))

(define unknown (→ Any) #t)
(handle dyn-cast
    ((conversion-failed (lambda (error)
                          (write-line (match (::reason error)
                                        ((UnsupportedInstance) "unsupported instance")
                                        (_ "wrong reason")))
                          (write-line (string-join (::expected error) ", ")))))
  (describe unknown)
  (unit))
