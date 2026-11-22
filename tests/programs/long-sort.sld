(import
 (snail core base)
 (snail core io))

(record Ranked
  ((key I64)
   (index I64)))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (let ((sorted (list-sort < (reverse (iota 30000)))))
    (write-line out (show (length sorted)))
    (write-line out (show (fold-left + 0 sorted)))
    (write-line out (show (list-ref sorted 29999))))
  (let ((sorted (list-sort (lambda (a b) (< (● a key) (● b key)))
                           (list (new Ranked (key 1) (index 0))
                                 (new Ranked (key 0) (index 1))
                                 (new Ranked (key 1) (index 2))
                                 (new Ranked (key 0) (index 3))))))
    (write-line out (string-join (map (lambda (item) (show (● item index))) sorted) ",")))
  (unit))
