(import
 (snail core base)
 (snail core io))

;; Each instance is single-threaded, so a handler may capture shared mutable
;; state: through an alias, a global, a local cell, a method that reads a
;; global, or a callback passed in. A handler must still be reusable, which
;; ordinary closures are, since they cannot capture a one-shot value.
(effect Counter ((tick (-> I64))))

(let* ((state (ref (ann 1 I64)))
       (callback (lambda () (ref-get state)))
       (alias callback))
  (display (handle Counter ((tick alias)) (tick)))
  (newline))

;; ANCHOR: counter
(define counter (ref (ann 10 I64)))
(define (count-up)
  (ref-set! counter (+ (ref-get counter) 1))
  (ref-get counter))
(display (handle Counter ((tick count-up)) (+ (tick) (tick))))
;; ANCHOR_END: counter
(newline)

(let ((state (ref (ann 3 I64))))
  (display (handle Counter ((tick (lambda () (let ((value (ref-get state))) value)))) (tick)))
  (newline))

(struct Number
  ((value I64)))
(typeclass (Read T) (: read-number (-> T I64 ! mut)))
(define reading (ref (ann 4 I64)))
(instance (Read Number) (define (read-number value) (+ (Number-value value) (ref-get reading))))
(display (handle Counter ((tick (lambda () (read-number (Number 1))))) (tick)))
(newline)

(: apply-handler (-> (-> I64 ! mut) I64 ! mut))
(define (apply-handler callback)
  (handle Counter ((tick callback)) (tick)))
(display (apply-handler (lambda () (ref-get reading))))
(newline)
