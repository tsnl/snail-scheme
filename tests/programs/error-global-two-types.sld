(import
 (snail core base))
;; One list, so one element type: the uses decide it together.
(define empty (Nil))
(define (numbers) (→ (List I64)) (Cons 1 empty))
(define (names) (→ (List String)) (Cons "a" empty))
