(import
 (snail core base)
 (snail core io)
 (only (snail core primitive) inherit-handlers))

(effect Reading ((read-number (Fn I64 → I64))))
(effect Pausing ((ctl pause-number (Fn I64 → I64))))
(effect Stopping ((ctl stop-text (Fn String → Never))))
(effect Finalized ((finalized (Fn I64 → Unit))))

(struct Counter
  ((value I64)))

(struct Resource
  ((value I64)))

(instance (Drop (! Finalized) Resource)
  (define (drop (resource Resource)) (→ Unit) (! Finalized)
    (match resource ((Resource value) (finalized value)))))

(define (ordinary) (→ I64)
  (handle Reading ((read-number (lambda (number) (+ number 3))))
    (read-number 4)))

(define (resumed) (→ I64)
  (handle Pausing ((pause-number (lambda (number resume) (+ 100 (resume (+ number 1))))))
    (+ 10 (pause-number 5))))

(define (aborted) (→ String)
  (handle Stopping ((stop-text (lambda (text) (string-append "caught: " text))))
    (absurd (stop-text "done"))))

(define (current-heap) (→ I64)
  (unsafe-total
   (lambda ()
     (let ((counter (Counter 0)))
       (handle Pausing
           ((pause-number (lambda (number resume)
                            (set! (● counter value) 7)
                            (resume number))))
         (+ (pause-number 2) (● counter value)))))))

(define (counted-scope) (→ Unit) (! mut Finalized)
  (let ((owner (rc (Resource 5))))
    (let ((alias owner))
      (drop alias))))

(define (finalized-value) (→ I64)
  (unsafe-total
   (lambda ()
     (let ((counter (Counter 0)))
       (handle Finalized ((finalized (lambda (value) (set! (● counter value) value))))
         (counted-scope))
       (● counter value)))))

(define (cancelled) (→ I64)
  (unsafe-total
   (lambda ()
     (let ((counter (Counter 0)))
       (handle Finalized ((finalized (lambda (value) (set! (● counter value) value))))
         (handle Pausing ((pause-number (lambda (number resume)
                                          (drop resume)
                                          number)))
           (let ((resource (Resource 8)))
             (pause-number 2)
             (drop resource)
             0)))
       (● counter value)))))

(define folded-ordinary (→ I64) (ordinary))
(define folded-resumed (→ I64) (resumed))
(define folded-aborted (→ String) (aborted))
(define folded-heap (→ I64) (current-heap))
(define folded-finalized (→ I64) (finalized-value))
(define folded-cancelled (→ I64) (cancelled))
(define add-nine (→ (Fn I64 → I64))
  ((lambda (base) (lambda (value) (+ base value))) 9))

(define recursive-sum (→ (Fn I64 → I64))
  (let ()
    (define (sum (value I64)) (→ I64)
      (if (= value 0) 0 (+ value (sum (- value 1)))))
    sum))

(define folded-sum (→ I64) (recursive-sum 5))

(define (bound-reader) (→ I64)
  (unsafe-total
   (lambda ()
     (let ((reader (handle Reading ((read-number (lambda (value) (+ value 20))))
                     (inherit-handlers (once (lambda () (read-number 3)))))))
       (reader)))))

(define folded-reader (→ I64) (bound-reader))

(effect Carrying ((read-delayed (Fn I64 → I64 ! Pausing))))

(define (hidden-handler) (→ I64)
  (handle Pausing ((pause-number (lambda (value resume) (resume (+ value 1)))))
    (handle Carrying ((read-delayed (lambda (value) (pause-number value))))
      (+ 1 (read-delayed 4)))))

(define (once-alias) (→ I64)
  (let ((value 7))
    (define (f) (→ I64) value)
    (let ((answer ((once f))))
      (drop (once f))
      (+ answer (f)))))

(define (capture-order) (→ I64)
  (unsafe-total
   (lambda ()
     (let ((counter (Counter 0)))
       (handle Finalized
           ((finalized
             (lambda (value) (set! (● counter value) (+ (* 10 (● counter value)) value)))))
         (let ((f (let ((alpha (rc (Resource 1))) (omega (rc (Resource 2))))
                    (lambda () (+ (● alpha value) (● omega value))))))
           (drop f)))
       (● counter value)))))

(struct Work
  ((action (FnOnce → Unit))
   (owner (Rc Resource))
   (attempts I64)))

(define (linear-replacement) (→ I64)
  (unsafe-total
   (lambda ()
     (let ((counter (Counter 0)))
       (handle Finalized ((finalized (lambda (value) (set! (● counter value) value))))
         (let* ((work (Work (once (lambda () (unit))) (rc (Resource 13)) 0))
                (work (Work-attempts-set work 1)))
           (drop work)))
       (● counter value)))))

(define folded-hidden (→ I64) (hidden-handler))
(define folded-alias (→ I64) (once-alias))
(define folded-order (→ I64) (capture-order))
(define folded-replacement (→ I64) (linear-replacement))

(define (main) (→ Unit) (! output-port)
  (write-line (show folded-ordinary))
  (write-line (show (ordinary)))
  (write-line (show folded-resumed))
  (write-line (show (resumed)))
  (write-line folded-aborted)
  (write-line (aborted))
  (write-line (show folded-heap))
  (write-line (show (current-heap)))
  (write-line (show folded-finalized))
  (write-line (show (finalized-value)))
  (write-line (show folded-cancelled))
  (write-line (show (cancelled)))
  (write-line (show (add-nine 4)))
  (write-line (show folded-sum))
  (write-line (show (recursive-sum 5)))
  (write-line (show folded-reader))
  (write-line (show (bound-reader)))
  (write-line (show folded-hidden))
  (write-line (show (hidden-handler)))
  (write-line (show folded-alias))
  (write-line (show (once-alias)))
  (write-line (show folded-order))
  (write-line (show (capture-order)))
  (write-line (show folded-replacement))
  (write-line (show (linear-replacement)))
  (unit))
