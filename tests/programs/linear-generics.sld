(import
 (snail core base)
 (snail core io))

;; A type variable is linear unless its definition requires (Copy A), so a
;; generic function that moves its arguments takes linear ones.
(define (swap (pair (Pair A B))) (→ (Pair B A)) (∀ (A B))
  (match pair
    ((Pair a b) (Pair b a))))

(define (say (text String)) (→ (FnOnce → Unit ! output-port))
  (once (lambda () (write-line text))))

;; A function that duplicates requires Copy, and is used at copyable types.
(define (twice (value A)) (→ (Pair A A)) (∀ (A)) (⊨ (Copy A))
  (Pair value value))

(define (main) (→ Unit) (! output-port)
  (match (swap (Pair (say "first") (say "second")))
    ((Pair a b) (call-once a) (call-once b)))
  ;; A list of linear values is linear itself, and map and for-each move
  ;; each element once.
  (for-each (lambda (work) (call-once work)) (map say (list "one" "two")))
  (match (twice "again")
    ((Pair a b) (write-line (string-append a b))))
  (unit))
