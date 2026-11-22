(import
 (snail core base)
 (snail core io))

;; Handler closures share explicitly supplied records. Each invocation has
;; its own initial state without using a shared module value.
(effect Counter ((tick (Fn → I64))))

;; ANCHOR: counter
(record CounterState
  ((value I64)))

(define (count-up (state CounterState)) (→ I64) (! mut)
  (set! (● state value) (+ (● state value) 1))
  (● state value))

(record Number
  ((value I64)
   (offset CounterState)))

(typeclass (Read T) (declare (read-number (value T)) (→ I64)))
(instance (Read Number)
  (define (read-number (value Number)) (→ I64)
    (+ (● value value) (● value offset value))))

(define (apply-handler (callback (Fn → I64))) (→ I64)
  (handle Counter ((tick callback)) (tick)))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (let* ((state (new CounterState (value 1)))
         (callback (lambda () (● state value)))
         (alias callback))
    (display out (handle Counter ((tick alias)) (tick)))
    (newline out))
  (let ((counter (new CounterState (value 10))))
    (display out (handle Counter ((tick (lambda () (count-up counter)))) (+ (tick) (tick)))))
  ;; ANCHOR_END: counter
  (newline out)
  (let ((state (new CounterState (value 3))))
    (display out (handle Counter ((tick (lambda () (● state value)))) (tick)))
    (newline out))
  (let ((reading (new CounterState (value 4))))
    (display out
     (handle Counter ((tick (lambda () (read-number (new Number (value 1) (offset reading))))))
       (tick)))
    (newline out)
    (display out (apply-handler (lambda () (● reading value))))
    (newline out))
  (unit))
