(import
 (snail core base)
 (snail core io))

;; `resume` runs the rest of the handled code at most once. It is an
;; ordinary function to the checker, so an implementation may call it
;; twice, as this one does, and the second call panics.
(effect Choose
  ((ctl choose (Fn → Bool))))

(define (both) (→ (List Bool)) (! output-port)
  (handle Choose ((choose (lambda (resume)
                            (let ((first (resume #t)))
                              (write-line "resumed once")
                              (append first (resume #f))))))
    (list (choose))))

(define (main) (→ Unit) (! output-port)
  (both)
  (write-line "not reached")
  (unit))
