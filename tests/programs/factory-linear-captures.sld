(import
 (snail core base)
 (snail core io))

(effect Finalized ((finalized (Fn I64 → Unit))))

(record Counter
  ((value I64)))

(record Resource
  ((value I64)))

(instance (Drop (! Finalized) Resource)
  (define (drop (resource Resource)) (→ Unit) (! Finalized)
    (match resource ((Resource value) (finalized value)))))

(define (make-work) (→ (Rc (FnOnce → Unit ! Finalized mut)))
  (unsafe-total
   (lambda ()
     (let ((alpha (new Resource (value 1)))
           (shared (rc (new Resource (value 2))))
           (omega (new Resource (value 3))))
       (rc (once (lambda () (drop alpha) (drop omega) (drop shared))))))))

(define (make-alias-work) (→ (Rc (FnOnce → Unit ! Finalized mut)))
  (unsafe-total (lambda ()
                  (let* ((alpha (rc (new Resource (value 1))))
                         (middle (rc (new Resource (value 2))))
                         (last alpha))
                    (rc (once (lambda () (drop alpha) (drop middle) (drop last))))))))

(define (alias-frozen) (→ (Rc (FnOnce → Unit ! Finalized mut))) (make-alias-work))

(define (nested-order) (→ I64)
  (unsafe-total
   (lambda ()
     (let ((counter (new Counter (value 0))))
       (handle Finalized
           ((finalized
             (lambda (value) (set! (● counter value) (+ (* 10 (● counter value)) value)))))
         (let ((alpha (new Resource (value 1))) (omega (new Resource (value 3))))
           ((once (lambda () (drop (once (lambda () (drop omega) (drop alpha)))))))))
       (● counter value)))))

(define (frozen) (→ (Rc (FnOnce → Unit ! Finalized mut))) (make-work))

(define (observe (make (Fn → (Rc (FnOnce → Unit ! Finalized mut))))) (→ I64)
  (unsafe-total
   (lambda ()
     (let ((counter (new Counter (value 0))))
       (handle Finalized
           ((finalized
             (lambda (value) (set! (● counter value) (+ (* 10 (● counter value)) value)))))
         (let ((work (make))) (drop work)))
       (● counter value)))))

(define (folded-direct) (→ I64) (observe make-work))
(define (folded-frozen) (→ I64) (observe (lambda () (frozen))))

(define (folded-alias) (→ I64) (observe (lambda () (alias-frozen))))
(define (folded-nested) (→ I64) (nested-order))

(define (main) (→ Unit) (! output-port)
  (write-line (show (folded-direct)))
  (write-line (show (folded-frozen)))
  (write-line (show (observe make-work)))
  (write-line (show (observe (lambda () (frozen)))))
  (write-line (show (folded-alias)))
  (write-line (show (observe make-alias-work)))
  (write-line (show (observe (lambda () (alias-frozen)))))
  (write-line (show (folded-nested)))
  (write-line (show (nested-order))))
