(import
 (snail-core base))
(effect Counter ((tick (-> I64))))
(struct Number
  ((value I64)))
(typeclass (Read T) (: read-number (-> T I64 ! mut)))
(define state (ref (ann 1 I64)))
(instance (Read Number) (define (read-number value) (ref-get state)))
(handle Counter ((tick (lambda () (read-number (Number 1))))) (tick))
