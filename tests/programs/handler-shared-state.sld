(import
 (snail core base)
 (snail core io))

;; Handler closures share explicitly supplied records. Each invocation has
;; its own initial state without using a shared module value.
(effect Counter ((tick (Fn → I64))))

;; ANCHOR: counter
(record Counter-state
  ((value I64)))

(define (count-up (state Counter-state)) (→ I64) (! Mut)
  (set! (● state value) (+ (● state value) 1))
  (● state value))

(record Number
  ((value I64)
   (offset Counter-state)))

(typeclass (Read T) (declare (read-number (value T)) (→ I64)))
(instance (Read Number)
  (define (read-number (value Number)) (→ I64)
    (+ (● value value) (● value offset value))))

(define (apply-handler (callback (Fn → I64))) (→ I64)
  (handle Counter ((tick callback)) (tick)))

(define (main) (→ Unit) (! Mut Output-port)
  (let* ((state (new Counter-state (value 1)))
         (callback (lambda () (● state value)))
         (alias callback))
    (display (handle Counter ((tick alias)) (tick)))
    (newline))
  (let ((counter (new Counter-state (value 10))))
    (display (handle Counter ((tick (lambda () (count-up counter)))) (+ (tick) (tick)))))
  ;; ANCHOR_END: counter
  (newline)
  (let ((state (new Counter-state (value 3))))
    (display (handle Counter ((tick (lambda () (● state value)))) (tick)))
    (newline))
  (let ((reading (new Counter-state (value 4))))
    (display
     (handle Counter ((tick (lambda () (read-number (new Number (value 1) (offset reading))))))
       (tick)))
    (newline)
    (display (apply-handler (lambda () (● reading value))))
    (newline))
  (unit))
