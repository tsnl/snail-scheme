(import
 (snail core base)
 (snail core io))

(record Ranked
  ((key I64)
   (index I64)))

(define (main) (→ Unit) (! output-port)
  (let ((sorted (list-sort < (reverse (iota 30000)))))
    (write-line (show (length sorted)))
    (write-line (show (fold-left + 0 sorted)))
    (write-line (show (list-ref sorted 29999))))
  (let ((sorted (list-sort (lambda (a b) (< (● a key) (● b key)))
                           (list (new Ranked (key 1) (index 0))
                                 (new Ranked (key 0) (index 1))
                                 (new Ranked (key 1) (index 2))
                                 (new Ranked (key 0) (index 3))))))
    (write-line (string-join (map (lambda (item) (show (● item index))) sorted) ",")))
  (unit))
