(import
 (snail core base)
 (snail core io))

(struct Resource
  ((value I64)))

(instance (Drop (! output-port) Resource)
  (define (drop (resource Resource)) (→ Unit) (! output-port)
    (match resource ((Resource value) (display value) (newline)))))

(define (main) (→ Unit) (! mut output-port)
  (let* ((items (vector)) (alias items))
    (do ((index 1 (+ index 1))) ((= index 6)) (vector-push! items (rc (Resource index))))
    (write (vector-length alias)) (newline)
    (let ((weak (rc-downgrade (vector-ref items 4))))
      (match (vector-pop! alias)
        ((Some item) (write (● item value)) (newline))
        ((None) (panic "missing resource")))
      (match (weak-rc-upgrade weak)
        ((None) (write-line "popped resource finalized"))
        ((Some item) (panic "spare capacity retained an owner"))))
    (vector-set! items 0 (vector-ref items 0))
    (vector-push! alias (rc (Resource 6)))
    (let ((copy (vector-copy items)))
      (vector-copy! items 1 items 0 3)
      (write (● (vector-ref copy 3) value)) (newline))
    (write-line "leaving vector"))
  (write-line "done"))
