(define-library (sample specialization)
  (export first second advance round-trip fixed nested-values)
  (import
   (snail core base))
  (begin

    (: counter (Ref I64))
    (define counter (ref 0))

    (: advance (-> I64 ! mut))
    (define (advance)
      (let ((next (+ (ref-get counter) 1)))
        (ref-set! counter next)
        next))

    ;; Emission reaches these in reverse order. Their initialization must
    ;; still follow source order, including the otherwise unused value.
    (: first I64)
    (define first (advance))
    (: second I64)
    (define second (+ first (advance)))
    (: unreferenced I64)
    (define unreferenced (advance))

    ;; Each concrete nested-values initializer must follow the matching
    ;; empty-values initializer, including copies made by another library.
    (: empty-values (All (A) (requires (Copy A)) (List A)))
    (define empty-values (Nil))
    (: nested-values (All (A) (requires (Copy A)) (List (List A))))
    (define nested-values (Cons empty-values (Nil)))

    ;; Both specializations reserve their names before discovering the
    ;; back-edge. Repeated references reuse the reserved implementation.
    (: outbound (All (A) (-> A I64 A)))
    (define (outbound value count)
      (if (= count 0) value (inbound value (- count 1))))

    (: inbound (All (A) (-> A I64 A)))
    (define (inbound value count)
      (if (= count 0) value (outbound value (- count 1))))

    (: fixed (-> I64 I64))
    (define (fixed value) (+ value 1))

    (: round-trip (All (A) (-> A I64 A)))
    (define round-trip outbound)))
