(import
 (snail core base)
 (snail core io))

;; A type variable is linear unless its definition requires (Copy A), so a
;; generic function that moves its arguments takes linear ones.
(: swap (All (A B) (-> (Pair A B) (Pair B A))))
(define (swap pair)
  (match pair
    ((Pair a b) (Pair b a))))

(: say (-> String (FnOnce Unit ! console)))
(define (say text)
  (once (lambda () (write-line text))))

(match (swap (Pair (say "first") (say "second")))
  ((Pair a b) (call-once a) (call-once b)))

;; A list of linear values is linear itself, and map and for-each move
;; each element once.
(for-each (lambda (work) (call-once work)) (map say (list "one" "two")))

;; A function that duplicates requires Copy, and is used at copyable types.
(: twice (All (A) (requires (Copy A)) (-> A (Pair A A))))
(define (twice value)
  (Pair value value))

(match (twice "again")
  ((Pair a b) (write-line (string-append a b))))
