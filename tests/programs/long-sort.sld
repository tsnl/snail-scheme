(import
 (snail core base)
 (snail core io))

(struct Ranked
  ((key I64)
   (index I64)))

(define (main) (→ Unit) (! output-port)
  (let ((sorted (list-sort < (reverse (iota 30000)))))
    (write-line (show (length sorted)))
    (write-line (show (fold-left + 0 sorted)))
    (write-line (show (list-ref sorted 29999))))
  (let ((sorted (list-sort (lambda (a b) (< (● a key) (● b key)))
                           (list (Ranked 1 0) (Ranked 0 1) (Ranked 1 2) (Ranked 0 3)))))
    (write-line (string-join (map (lambda (item) (show (● item index))) sorted) ",")))
  (unit))
