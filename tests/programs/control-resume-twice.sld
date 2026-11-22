(import
 (snail core base)
 (snail core io))

;; `resume` runs the rest of the handled code at most once. It is an
;; ordinary function to the checker, so an implementation may call it
;; twice, as this one does, and the second call panics.
(effect Choose
  ((ctl choose (Fn → Bool))))

(define (both (out OutputPort)) (→ (List Bool)) (! mut)
  (handle Choose ((choose (lambda (resume)
                            (let ((first (resume #t)))
                              (write-line out "resumed once")
                              (append first (resume #f))))))
    (list (choose))))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (both out)
  (write-line out "not reached")
  (unit))
