(import
 (snail core base)
 (snail core io))

;; `resume` runs the rest of the body at most once. It is an ordinary
;; function to the checker, so a handler may call it twice, as this one
;; does, and the second call panics.
(define choosing (→ (Prompt Unit Bool)) (make-prompt))

(define (both (out OutputPort)) (→ (List Bool)) (! mut)
  (with-prompt choosing
               (lambda () (list (suspend choosing (unit))))
               (lambda (value resume)
                 (let ((first (resume #t)))
                   (write-line out "resumed once")
                   (append first (resume #f))))))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (both out)
  (write-line out "not reached")
  (unit))
