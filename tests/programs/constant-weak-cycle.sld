(import
 (snail core base)
 (snail core io))

(effect Finalized ((finalized (Fn I64 → Unit))))

(struct Counter
  ((value I64)))

(struct Resource
  ((value I64)))

(instance (Drop (! Finalized) Resource)
  (define (drop (resource Resource)) (→ Unit) (! Finalized)
    (match resource ((Resource value) (finalized value)))))

(struct Ring
  ((next (Option Ring))
   (owner (Rc Resource))))

(define (make-weak) (→ (WeakRc Resource))
  (unsafe-total
   (lambda ()
     (let* ((owner (rc (Resource 7)))
            (ring (Ring (None) owner)))
       (set! (● ring next) (Some ring))
       (rc-downgrade owner)))))

(define weak (→ (WeakRc Resource)) (make-weak))

(define (read-weak) (→ I64)
  (unsafe-total
   (lambda ()
     (let ((counter (Counter 0)))
       (handle Finalized
           ((finalized (lambda (value) (set! (● counter value) value))))
         (match (weak-rc-upgrade weak)
           ((Some owner) (drop owner))
           ((None) (unit))))
       (● counter value)))))

(define folded (→ I64) (read-weak))

(define (source-alive) (→ I64)
  (unsafe-total
   (lambda ()
     (match (weak-rc-upgrade (make-weak))
       ((Some owner) (● owner value))
       ((None) -1)))))

(define (main) (→ Unit) (! output-port)
  (write-line (show folded))
  (write-line (show (read-weak)))
  (write-line (show (source-alive))))
