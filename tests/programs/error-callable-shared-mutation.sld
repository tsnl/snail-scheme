(import
 (snail core base))

(struct Counter
  ((value I64)))

(instance (Drop (!) Counter)
  (define drop (lambda (counter) (match counter ((Counter _) (unit))))))

(define main
  (lambda ()
    (let* ((counter (Counter 0))
           (advance (ann (lambda () (set! (● counter value) 1))
                         (Fn → Unit ! mut))))
      (drop advance))
    (unit)))
