(import
 (snail core base)
 (snail core io))

(struct Counter
  ((value I64)))

(define counter (→ Counter) (Counter 0))

(define (tick) (→ I64)
  (unsafe-total
   (lambda ()
     (set! (● counter value) (+ 1 (● counter value)))
     (● counter value))))

;; Dependencies are demanded in expression order, regardless of source order.
(define answer (→ I64) (+ later later))
(define later (→ I64) (tick))
(define zero (→ I64) (begin (tick) 0))
(define false (→ Bool) (begin (tick) #f))
(define unused (→ I64) (panic "unused initializer ran"))
(define unused-cycle (→ I64) (+ unused-cycle 1))

;; Constructing a closure does not read globals in its body.
(define recursive (→ (Fn I64 → I64))
  (let ((base 7))
    (lambda (n) (if (= n 0) base (recursive (- n 1))))))

(define (even (n I64)) (→ Bool) (if (= n 0) #t (odd (- n 1))))
(define (odd (n I64)) (→ Bool) (if (= n 0) #f (even (- n 1))))

(define (main) (→ Unit) (! output-port)
  (write-line (show (● counter value)))
  (write-line (show answer))
  (write-line (show answer))
  (write-line (show (+ zero zero)))
  (write-line (show (or false false)))
  (write-line (show (● counter value)))
  (write-line (show (recursive 100000)))
  (write-line (show (even 100000))))
