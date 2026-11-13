(define-library (sample specialization)
  (export first second round-trip fixed nested-values)
  (import
   (snail core base))
  (begin

    ;; Lazy values follow dependencies, including forward ones.
    (define (second) (→ I64) (+ (first) 2))
    (define (first) (→ I64) (+ (origin) 1))
    (define (origin) (→ I64) 0)

    ;; Stateless templates expand at each type; allocating generic values
    ;; are ordinary constructor functions, including across libraries.
    (define (empty-values) (→ (List A)) (∀ (A)) (⊨ (Copy A)) (Nil))
    (define (nested-values) (→ (List (List A))) (∀ (A)) (⊨ (Copy A)) (Cons (empty-values) (Nil)))

    ;; Both specializations reserve their names before discovering the
    ;; back-edge. Repeated references reuse the reserved implementation.
    (define (outbound (value A) (count I64)) (→ A) (∀ (A))
      (if (= count 0) value (inbound value (- count 1))))

    (define (inbound (value A) (count I64)) (→ A) (∀ (A))
      (if (= count 0) value (outbound value (- count 1))))

    (define (fixed (value I64)) (→ I64) (+ value 1))

    (define (round-trip (left A) (right I64)) (→ A) (∀ (A))
      (outbound left right))))
