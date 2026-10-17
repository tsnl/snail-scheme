(import
 (lofi base))
(define-extern record "instance.probe" "record" (-> I64 Unit))

;; Conversion operands have an observable effect before either return or trap.
(def effects (ref 0))
(def effect-count (-> I32) (lambda () (ref-get effects)))
(def integer-operation (ref i64->i32))
(def float-operation (ref f64->f32))
(def touch (All (T) (-> T T))
     (lambda (value) (begin (ref-set! effects (+ (ref-get effects) 1)) (record (ann 1 I64)) value)))

(def narrow-integer (-> Bool I64 I32)
     (lambda (indirect value)
       (if indirect ((ref-get integer-operation) (touch value)) (i64->i32 (touch value)))))
(def narrow-float (-> Bool F64 F32)
     (lambda (indirect value)
       (if indirect ((ref-get float-operation) (touch value)) (f64->f32 (touch value)))))

;; Discarding a result preserves its trap; an untaken branch has no effects.
(def narrow-control (-> Bool I32 I32)
     (lambda (indirect mode)
       (if (< mode 2)
           (if (= mode 1) (begin (narrow-integer indirect (ann 2147483648 I64)) 42) 42)
           (if (= mode 3) (begin (narrow-float indirect 1e300) 42) 42))))
42
