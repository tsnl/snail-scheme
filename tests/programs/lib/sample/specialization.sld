(define-library (sample specialization)
  (export first second round-trip fixed nested-values)
  (import
   (snail core base))
  (begin

    ;; Constants are forced through dependencies, including forward ones.
    (define second (→ I64) (+ first 2))
    (define first (→ I64) (+ origin 1))
    (define origin (→ I64) 0)

    ;; Each specialization instantiates the same fully evaluated constant,
    ;; including references from another library.
    (define empty-values (→ (List A)) (∀ A) (⊨ (Copy A)) (Nil))
    (define nested-values (→ (List (List A))) (∀ A) (⊨ (Copy A)) (Cons empty-values (Nil)))

    ;; Both specializations reserve their names before discovering the
    ;; back-edge. Repeated references reuse the reserved implementation.
    (define (outbound (value A) (count I64)) (→ A) (∀ A)
      (if (= count 0) value (inbound value (- count 1))))

    (define (inbound (value A) (count I64)) (→ A) (∀ A)
      (if (= count 0) value (outbound value (- count 1))))

    (define (fixed (value I64)) (→ I64) (+ value 1))

    (define round-trip (→ (Fn A I64 → A)) (∀ A) outbound)))
