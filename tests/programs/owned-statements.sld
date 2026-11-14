(import
 (snail core base)
 (snail core io))

;; A Holder is linear: it has a FnOnce field. Matching it moves the field
;; out, and the clause must use it once: here it drops it uncalled.
(record Holder
  ((work (FnOnce → Unit ! output-port))))

(define (main) (→ Unit) (! output-port)
  (match (new Holder (work (once (lambda () (write-line "a")))))
    ((Holder work)
     (drop work)
     (write-line "first")))
  (match (new Holder (work (once (lambda () (write-line "b")))))
    ((Holder work)
     (drop work)
     (write-line "second")))
  (unit))
