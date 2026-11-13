(import
 (snail core base)
 (snail core io))

;; Handler closures share explicitly supplied records. Each invocation owns
;; its initial state without using a shared module value.
(effect Counter ((tick (Fn → I64))))

;; ANCHOR: counter
(struct CounterState
  ((value I64)))

(define (count-up (state CounterState)) (→ I64) (! mut)
  (set! (● state value) (+ (● state value) 1))
  (● state value))

(struct Number
  ((value I64)
   (offset CounterState)))

(typeclass (Read T) (: read-number (Fn T → I64)))
(instance (Read Number)
  (define (read-number (value Number)) (→ I64)
    (+ (● value value) (● value offset value))))

(define (apply-handler (callback (Fn → I64))) (→ I64)
  (handle Counter ((tick callback)) (tick)))

(define (main) (→ Unit) (! mut output-port)
  (let* ((state (CounterState 1))
         (callback (lambda () (● state value)))
         (alias callback))
    (display (handle Counter ((tick alias)) (tick)))
    (newline))
  (let ((counter (CounterState 10)))
    (display (handle Counter ((tick (lambda () (count-up counter)))) (+ (tick) (tick)))))
  ;; ANCHOR_END: counter
  (newline)
  (let ((state (CounterState 3)))
    (display (handle Counter ((tick (lambda () (● state value)))) (tick)))
    (newline))
  (let ((reading (CounterState 4)))
    (display (handle Counter ((tick (lambda () (read-number (Number 1 reading))))) (tick)))
    (newline)
    (display (apply-handler (lambda () (● reading value))))
    (newline))
  (unit))
