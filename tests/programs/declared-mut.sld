(import
 (snail core base)
 (snail core io))

;; An instance method has its class method's signature, even when this
;; instance needs less of it: a `Mut` it never uses.
(record Seen
  ((count I64)))

(typeclass (Note T)
  (declare (note (mut Mut) (seen Seen) (value T)) (→ Unit)))

(instance (Note I64)
  (define (note (mut Mut) (seen Seen) (n I64)) (→ Unit)
    (set! mut (● seen count) (+ (● seen count) n))))

(instance (Note Bool)
  (define (note (mut Mut) (seen Seen) (b Bool)) (→ Unit)
    (unit)))

;; Calls `action` twice, with whatever it was made with.
(define (twice (action (Fn → Unit))) (→ Unit)
  (action)
  (action))

(define (main (mut Mut) (out OutputPort)) (→ Unit)
  (let ((seen (new Seen (count 0))))
    (note mut seen 41)
    (note mut seen #t)
    (twice (lambda () (note mut seen 2)))
    (write-line out (i64->string (● seen count))))
  (unit))
