(import
 (snail core base)
 (snail core io)
 (only (snail core primitive) inherit-handlers))

(effect Reading ((read-number (Fn I64 → I64))))
(effect Pausing ((ctl pause-number (Fn I64 → I64))))
(effect Stopping ((ctl stop-text (Fn String → Never))))

(record Counter
  ((value I64)))

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
     (let ((counter (new Counter (value 0))))
       (handle Pausing
           ((pause-number (lambda (number resume)
                            (set! (● counter value) 7)
                            (resume number))))
         (+ (pause-number 2) (● counter value)))))))

(define (folded-ordinary) (→ I64) (ordinary))
(define (folded-resumed) (→ I64) (resumed))
(define (folded-aborted) (→ String) (aborted))
(define (folded-heap) (→ I64) (current-heap))
(define (add-nine) (→ (Fn I64 → I64))
  ((lambda (base) (lambda (value) (+ base value))) 9))

(define (recursive-sum) (→ (Fn I64 → I64))
  (let ()
    (define (sum (value I64)) (→ I64)
      (if (= value 0) 0 (+ value (sum (- value 1)))))
    sum))

(define (recursive-capture) (→ (Fn I64 → I64))
  (let ((base 2))
    (define (sum (value I64)) (→ I64)
      (if (= value 0) base (+ value (sum (- value 1)))))
    sum))

(define (folded-sum) (→ I64) ((recursive-sum) 5))

(define (bound-reader) (→ I64)
  (unsafe-total
   (lambda ()
     (let ((reader (handle Reading ((read-number (lambda (value) (+ value 20))))
                     (inherit-handlers (lambda () (read-number 3))))))
       (reader)))))

(define (folded-reader) (→ I64) (bound-reader))

(effect Carrying ((read-delayed (Fn I64 → I64 ! Pausing))))

(define (hidden-handler) (→ I64)
  (handle Pausing ((pause-number (lambda (value resume) (resume (+ value 1)))))
    (handle Carrying ((read-delayed (lambda (value) (pause-number value))))
      (+ 1 (read-delayed 4)))))

(define (once-alias) (→ I64)
  (let ((value 7))
    (define (f) (→ I64) value)
    (let ((answer (f)))
      (+ answer (f)))))

(define (folded-hidden) (→ I64) (hidden-handler))
(define (folded-alias) (→ I64) (once-alias))


(define (main (out OutputPort)) (→ Unit) (! mut)
  (write-line out (show (folded-ordinary)))
  (write-line out (show (ordinary)))
  (write-line out (show (folded-resumed)))
  (write-line out (show (resumed)))
  (write-line out (folded-aborted))
  (write-line out (aborted))
  (write-line out (show (folded-heap)))
  (write-line out (show (current-heap)))
  (write-line out (show ((add-nine) 4)))
  (write-line out (show (folded-sum)))
  (write-line out (show ((recursive-sum) 5)))
  (write-line out (show (folded-reader)))
  (write-line out (show (bound-reader)))
  (write-line out (show (folded-hidden)))
  (write-line out (show (hidden-handler)))
  (write-line out (show (folded-alias)))
  (write-line out (show (once-alias)))
  (write-line out (show ((recursive-capture) 5)))
  (unit))
