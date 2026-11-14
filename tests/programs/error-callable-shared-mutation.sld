(import
 (snail core base))

(record Counter
  ((value I64)))

(instance (Drop (!) Counter)
  (define (drop (counter Counter)) (→ Unit)
    (match counter ((Counter _) (unit)))))

(define main
  (lambda ()
    (let* ((counter (new Counter (value 0)))
           (advance (ann (lambda () (set! (● counter value) 1))
                         (Fn → Unit ! mut))))
      (drop advance))
    (unit)))
