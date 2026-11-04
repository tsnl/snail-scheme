(import
 (snail core base))

(effect log ((record (-> Unit))))
(typeclass (Add e A B)
  (type Output)
  (: add (-> A B Output ! e)))
(define-instance-set sources
  (instance (Add (!) I64 I64)
    (type Output I64)
    (define (add a b) (+ a b)))
  (instance (Add (! log) I64 F64)
    (type Output F64)
    (define (add a b) (record) (+ (i64->f64 a) b))))
(with-instances (sources)
                (define-instance-set dynamic
                  (dynamic-instances Add (I64 I64) (I64 F64))))
(with-instances (dynamic)
                (: too-small (-> I64 Any Any ! dyn-cast))
                (define (too-small a b) (add a b)))
