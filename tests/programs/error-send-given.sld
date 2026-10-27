(import
 (snail-core base))

(: transfer (All (T) (requires (Send T)) (-> T T)))
(define (transfer value) value)

(: forged (All () (requires (Send (Ref I64))) (List (Ref I64))))
(define forged (transfer (list (ref (ann 1 I64)))))
