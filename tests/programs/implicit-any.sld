(import
 (snail core base)
 (snail core io))

(: boxed Any)
(define boxed 41)

(: integer (-> Any I64 ! dyn-cast))
(define (integer value) value)

(: package (-> I64 Any))
(define (package value) value)

(: increment (-> I64 I64))
(define (increment value) (+ value 1))

(: first (All (T) (requires (Copy T)) (-> T T T)))
(define (first a b) a)

(struct Holder
  ((value Any)))

(: unboxed I64)
(define unboxed (match (try-convert boxed I64) ((Ok value) value) ((Err _) -1)))

(handle dyn-cast
    ((conversion-failed (lambda (_) (write-line "unexpected conversion failure"))))
  (display (increment boxed))
  (newline)
  (display (integer (package unboxed)))
  (newline)
  (display (ann (Holder-value (Holder 7)) I64))
  (newline)
  (display (increment (first boxed 1)))
  (newline)
  (display (increment (first 1 boxed)))
  (newline)
  (display (type-test (first boxed boxed) I64))
  (newline))

(: function Any)
(define function (ann (lambda (x) (+ x 1)) (-> I64 I64)))
(handle dyn-cast
    ((conversion-failed (lambda (_) (write-line "unexpected conversion failure"))))
  (display ((ann function (-> I64 I64)) 9))
  (newline))

(: condition Any)
(define condition #t)
(handle dyn-cast
    ((conversion-failed (lambda (_) (write-line "unexpected conversion failure"))))
  (display (if condition 1 2))
  (newline)
  (display (type-test 7 I64))
  (newline))

(effect ask
  ((ctl answer (-> Never))))
(handle dyn-cast
    ((conversion-failed (lambda (_) (write-line "unexpected conversion failure"))))
  (display (ann (handle ask
                    ((answer (lambda () boxed)))
                  (ann (absurd (answer)) I64)) I64))
  (newline))
