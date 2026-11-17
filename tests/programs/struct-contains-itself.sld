(import
 (snail core base)
 (snail core io))

;; Every Node would hold another Node, so no program can build one, but
;; declaring it is valid: a function that would take one is never called.
(record Node
  ((next Node)))

(define (depth (node Node) (limit I64)) (→ I64)
  (if (= limit 0) 0 (+ 1 (depth (● node next) (- limit 1)))))

(define (main) (→ Unit) (! output-port)
  (write-line "declared"))
