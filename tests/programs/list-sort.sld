(import
 (snail core base)
 (snail core io))

;; Equal keys keep the payloads' input order; sorting leaves the input intact.
(define (entries) (→ (List (Pair I64 String)))
  (list (Pair 2 "a") (Pair 1 "b") (Pair 2 "c") (Pair 1 "d") (Pair 2 "e")))

;; A permutation exercises the halves and merges beyond a few elements.

(define (main) (→ Unit) (! output-port)
  (define shuffled (→ (List I64)) (map (lambda (index) (remainder (* index 97) 257)) (iota 257)))

  (write-line (repr (ann (list-sort < (Nil)) (List I64))))
  (write-line (repr (list-sort < (list 42))))
  (write-line (repr (list-sort > (list 1 3 2 3 0))))
  (write-line
   (repr (map (lambda (record) (● record second))
              (list-sort (lambda (a b) (< (● a first) (● b first))) (entries)))))
  (write-line (repr (map (lambda (record) (● record second)) (entries))))
  (write-line (show (string=? (repr (list-sort < shuffled)) (repr (iota 257)))))
  (unit))
