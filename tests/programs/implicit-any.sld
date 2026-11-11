(import
 (snail core base)
 (snail core io))

(define boxed (→ Any) 41)

(define (integer (value Any)) (→ I64) (! dyn-cast) value)

(define (package (value I64)) (→ Any) value)

(define (increment (value I64)) (→ I64) (+ value 1))

(define (first (a T) (b T)) (→ T) (∀ T) (⊨ (Copy T)) a)

(struct Holder
  ((value Any)))

(define unboxed (→ I64) (match (try-convert boxed I64) ((Ok value) value) ((Err _) -1)))

(handle dyn-cast
    ((conversion-failed (lambda (_) (write-line "unexpected conversion failure"))))
  (display (increment boxed))
  (newline)
  (display (integer (package unboxed)))
  (newline)
  (display (ann (::value (Holder 7)) I64))
  (newline)
  (display (increment (first boxed 1)))
  (newline)
  (display (increment (first 1 boxed)))
  (newline)
  (display (type-test (first boxed boxed) I64))
  (newline))

(define function (→ Any) (ann (lambda (x) (+ x 1)) (dyn (Fn I64 → I64))))
(handle dyn-cast
    ((conversion-failed (lambda (_) (write-line "unexpected conversion failure"))))
  (display ((ann function (dyn (Fn I64 → I64))) 9))
  (newline))

(define condition (→ Any) #t)
(handle dyn-cast
    ((conversion-failed (lambda (_) (write-line "unexpected conversion failure"))))
  (display (if condition 1 2))
  (newline)
  (display (type-test 7 I64))
  (newline))

(effect ask
  ((ctl answer (dyn (Fn → Never)))))
(handle dyn-cast
    ((conversion-failed (lambda (_) (write-line "unexpected conversion failure"))))
  (display (ann (handle ask
                    ((answer (lambda () boxed)))
                  (ann (absurd (answer)) I64)) I64))
  (newline))
