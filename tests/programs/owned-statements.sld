(import
 (snail core base)
 (snail core io))

;; A Holder is linear: it has a Once field. Matching it moves the field
;; out, and the clause must use it once: here it drops it uncalled.
(struct Holder
  ((work (Once (-> Unit ! console)))))

(match (Holder (once (lambda () (write-line "a"))))
  ((Holder work)
   (drop work)
   (write-line "first")))

(match (Holder (once (lambda () (write-line "b"))))
  ((Holder work)
   (drop work)
   (write-line "second")))
