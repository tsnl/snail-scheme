(import
 (snail core base))

;; Each instance a dynamic-instances form generates is compared with those
;; before it in its set, the form's earlier ones too. The heads of these
;; pairs are (Any I64), (I64 Any), (Any Any) and (Any F) for the function
;; type F, which overlaps any type, so the last overlaps the first. The
;; sources are in two sets, which are compared apart.
(typeclass (Op e A B)
  (type Output)
  (: op (impl (Fn A B -> Output ! e))))
(define-instance-set numbers
  (instance (Op (!) I64 I64)
    (type Output I64)
    (define (op a b) a)))
(define-instance-set functions
  (instance (Op (!) I64 (dyn (Fn I64 -> I64)))
    (type Output I64)
    (define (op a f) (f a))))
(with-instances (numbers functions)
                (define-instance-set dynamic
                  (dynamic-instances Op (I64 I64) (I64 (dyn (Fn I64 -> I64))))))
