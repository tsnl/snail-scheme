(import
 (snail core base)
 (snail core io)
 (gradual describe))

(define unknown (→ Any) #t)
(handle dyn-cast
    ((conversion-failed (lambda (error)
                          (write-line (match (● error reason)
                                        ((UnsupportedInstance) "unsupported instance")
                                        (_ "wrong reason")))
                          (write-line (string-join (● error expected) ", ")))))
  (describe unknown)
  (unit))
