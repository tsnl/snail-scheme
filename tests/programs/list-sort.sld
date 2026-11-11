(import
 (snail core base)
 (snail core io))

(write-line (show (ann (list-sort < (Nil)) (List I64))))
(write-line (show (list-sort < (list 42))))
(write-line (show (list-sort > (list 1 3 2 3 0))))

;; Equal keys keep the payloads' input order; sorting leaves the input intact.
(define entries (→ (List (Pair I64 String)))
  (list (Pair 2 "a") (Pair 1 "b") (Pair 2 "c") (Pair 1 "d") (Pair 2 "e")))

(write-line
 (show (map (lambda (record) (● record second))
            (list-sort (lambda (a b) (< (● a first) (● b first))) entries))))
(write-line (show (map (lambda (record) (● record second)) entries)))

;; A permutation exercises the halves and merges beyond a few elements.
(define shuffled (→ (List I64)) (map (lambda (index) (remainder (* index 97) 257)) (iota 257)))
(write-line (show (string=? (show (list-sort < shuffled)) (show (iota 257)))))
