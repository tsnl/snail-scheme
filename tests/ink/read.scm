(import
 (snail core base)
 (snail core io)
 (snail shell game dialogue)
 (radio lines))

(define (main (out OutputPort)) (→ Unit)
  (let ((book conversation))
    (match (open-dialogue book)
      ((Some start)
       (write-line out (string-append (● start page) " " (spoken book start)))
       (for-each (lambda (i)
                   (match (answer-dialogue book start i)
                     ((Some reply)
                      (write-line out (string-append (● (list-ref (replies book start) i) text) " "
                                                     (● reply page) " " (spoken book reply))))
                     (_ (panic "missing answer")))) (iota (length (replies book start)))))
      (_ (panic "missing entry")))))
