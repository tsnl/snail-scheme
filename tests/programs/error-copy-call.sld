(import
 (snail core base))

(define (count (items (List T))) (→ I64) (∀ (T)) (⊨ (Drop (!) T)) (length items))

(define main
  (lambda ()
    (count (list 1 2))
    (unit)))
