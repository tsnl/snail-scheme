(import
 (snail core base))
(define (consuming (function F)) (→ Unit) (! e) (∀ F e) (⊨ (FnOnce F → Unit ! e)) (function))
(define (shared (function F)) (→ Unit) (! e) (∀ F e) (⊨ (Fn F → Unit ! e)) (consuming function))
