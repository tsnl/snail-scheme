(import
 (snail core base)
 (snail core io)
 (prefix (associated-policy) p:))

(define (forward (a A) (b B))
  (→ (p:Combine.Output A B))
  (∀ A B)
  (⊨ (p:Combine A B))
  (p:generic a b))

(with-instances (p:description)
                (display (forward (ann 2 I64) (ann 3 I64)))
                (newline)
                (display ((p:make-adder 2) 3))
                (newline))
(with-instances (p:addition p:addition)
                (display (forward (ann 2 I64) (ann 3 I64)))
                (newline))
