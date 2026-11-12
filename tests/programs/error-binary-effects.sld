(import
 (snail core base))

(effect log ((record (Fn → Unit))))
(typeclass (Add e A B)
  (type Output)
  (: add (Fn A B → Output ! e)))
(define-instance-set sources
  (instance (Add (!) I64 I64)
    (type Output I64)
    (define add (lambda (a b) (+ a b))))
  (instance (Add (! log) I64 F64)
    (type Output F64)
    (define add (lambda (a b) (record) (+ (i64->f64 a) b)))))
(with-instances (sources)
                (define-instance-set dynamic
                  (dynamic-instances Add (I64 I64) (I64 F64))))
(with-instances (dynamic)
                (define (too-small (a I64) (b Any)) (→ Any) (! dyn-cast) (add a b)))
