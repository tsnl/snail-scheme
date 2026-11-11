(define-library (sample specialization)
  (export first second advance round-trip fixed nested-values)
  (import
   (snail core base))
  (begin

    (define counter (→ (Ref I64)) (ref 0))

    (define (advance) (→ I64) (! mut)
      (let ((next (+ (ref-get counter) 1)))
        (ref-set! counter next)
        next))

    ;; Emission reaches these in reverse order. Their initialization must
    ;; still follow source order, including the otherwise unused value.
    (define first (→ I64) (advance))
    (define second (→ I64) (+ first (advance)))
    (define unreferenced (→ I64) (advance))

    ;; Each concrete nested-values initializer must follow the matching
    ;; empty-values initializer, including copies made by another library.
    (define empty-values (→ (List A)) (∀ A) (⊨ (Copy A)) (Nil))
    (define nested-values (→ (List (List A))) (∀ A) (⊨ (Copy A)) (Cons empty-values (Nil)))

    ;; Both specializations reserve their names before discovering the
    ;; back-edge. Repeated references reuse the reserved implementation.
    (define (outbound (value A) (count I64)) (→ A) (∀ A)
      (if (= count 0) value (inbound value (- count 1))))

    (define (inbound (value A) (count I64)) (→ A) (∀ A)
      (if (= count 0) value (outbound value (- count 1))))

    (define (fixed (value I64)) (→ I64) (+ value 1))

    (define round-trip (→ (dyn (Fn A I64 → A))) (∀ A) outbound)))
