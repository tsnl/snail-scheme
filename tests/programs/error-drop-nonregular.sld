(import
 (snail core base))

;; A nest holds pairs of what it holds one level down, so its glue would
;; need a function for every depth.
(enum (Nest A)
  (Flat
   ((value A)))
  (Deeper
   ((inner (Nest (Pair A A))))))

(define (release (nest (Nest (FnOnce → Unit)))) (→ Unit)
  (drop nest))
