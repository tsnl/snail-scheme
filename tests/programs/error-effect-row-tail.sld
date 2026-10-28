(import
 (snail core base))

;; Unrelated quantified tails cannot be treated as interchangeable.
(: escape (All (A e f) (-> (-> A ! e) A ! f)))
(define (escape action) (action))
