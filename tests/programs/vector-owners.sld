(import
 (snail core base)
 (snail core io))

(record Resource
  ((value I64)))

(instance (Drop (! output-port) Resource)
  (define (drop (resource Resource)) (→ Unit) (! output-port)
    (match resource ((Resource value) (display value) (newline)))))

(define (main) (→ Unit) (! mut output-port)
  (let* ((items (vector-generate 5 (lambda (index) (rc (new Resource (value (+ index 1)))))))
         (alias items))
    (write (vector-length alias)) (newline)
    (let ((weak (rc-downgrade (vector-ref items 4))))
      (vector-set! alias 4 (rc (new Resource (value 6))))
      (match (weak-rc-upgrade weak)
        ((None) (write-line "replaced resource finalized"))
        ((Some item) (panic "replaced slot retained an owner"))))
    (vector-set! items 0 (vector-ref items 0))
    (let ((copy (vector-copy items)))
      (vector-copy! items 1 items 0 3)
      (write (● (vector-ref copy 3) value)) (newline))
    (write-line "leaving vector"))
  (write-line "done"))
