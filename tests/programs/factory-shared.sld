(import
 (snail core base)
 (snail core io))

(effect Log ((log-value (Fn I64 → Unit))))

(record Token
  ((value I64)))

(instance (Drop (! Log) Token)
  (define (drop (token Token)) (→ Unit) (! Log)
    (match token ((Token value) (log-value value)))))

(record Holders
  ((strong (Rc Token))
   (weak (WeakRc Token))))

(define (holders) (→ Holders)
  (let ((owner (rc (new Token (value 7)))))
    (new Holders (strong owner) (weak (rc-downgrade owner)))))

(define (dead) (→ (WeakRc Token))
  (unsafe-total
   (lambda ()
     (handle Log ((log-value (lambda (value) (unit))))
       (let ((owner (rc (new Token (value 9)))))
         (rc-downgrade owner))))))

(define (probe (value (WeakRc Token))) (→ I64) (! mut Log)
  (match (weak-rc-upgrade value)
    ((Some owner) (● owner value))
    ((None) -1)))

(record Cycle
  ((owner (Rc Token))
   (values (Vector (Rc Token)))
   (array (Vector (Rc Token)))
   (next (Option Cycle))))

(define (cyclic) (→ Cycle)
  (unsafe-total
   (lambda ()
     (let* ((owner (rc (new Token (value 11))))
            (node
             (new Cycle
               (owner owner)
               (values (vector-generate 1 (lambda (index) owner)))
               (array (make-vector 1 owner))
               (next (None)))))
       (set! (● node next) (Some node))
       node))))

(define (main) (→ Unit) (! mut output-port)
  (handle Log ((log-value (lambda (value) (write-line (string-append "drop " (show value))))))
    (let ((first (holders)) (second (holders)))
      (set! (● first strong value) 12)
      (write-line (show (probe (● first weak))))
      (write-line (show (probe (● second weak)))))
    (write-line (show (probe (dead))))
    (let ((node (cyclic)))
      (set! (● node next) (None))
      (write-line (show (● node owner value))))
    (let ((node (cyclic)))
      (set! (● node next) (None))
      (write-line (show (● node owner value)))))
  (unit))
