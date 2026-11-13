(import
 (snail core base)
 (snail core io)
 (handler helper))

(effect Counter ((tick (Fn → I64))))

(record CounterState
  ((count I64)))

(define (recursive (n I64)) (→ I64) (if (= n 0) 4 (recursive (- n 1))))

(define (main) (→ Unit) (! mut output-port)

  ;; Local mutation belongs to each invocation, not to its reusable environment.
  (display (handle Counter
               ((tick (lambda () (let ((cell (new CounterState (count 1))))
                                   (set! (● cell count) 7)
                                   (● cell count)))))
             (+ (tick) (tick))))
  (newline)
  (let* ((offset (ann 3 I64))
         (callback (lambda () (+ offset (recursive (answer)))))
         (alias callback))
    (display (handle Counter ((tick alias)) (tick)))
    (newline))
  ;; The outer read survives shadowing; the recursive loop and each pattern
  ;; binder belong to the invocation, even when their source names repeat.
  (let ((offset (ann 5 I64)))
    (display
     (handle Counter
         ((tick (lambda ()
                  (let ((offset (+ offset 1)))
                    (let loop ((rest (list offset)))
                      (match rest
                        ((Cons offset _) offset)
                        ((Nil) (loop (list 0)))))))))
       (tick)))
    (newline))
  (unit))
