(import
 (snail core base)
 (snail core io)
 (prefix (associated-policy) p:))

(: forward
   (All (A B)
        (requires (p:Combine A B))
        (impl (Fn A B -> (p:Combine.Output A B)))))
(define (forward a b) (p:generic a b))

(with-instances (p:description)
                (display (forward (ann 2 I64) (ann 3 I64)))
                (newline)
                (display ((p:make-adder 2) 3))
                (newline))
(with-instances (p:addition p:addition)
                (display (forward (ann 2 I64) (ann 3 I64)))
                (newline))
