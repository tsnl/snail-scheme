(import
 (snail core base))

;; `resume` is linear: an implementation calls it, or drops it, exactly once.
(effect Choose
  ((ctl choose (Fn → Bool))))

(define (both) (→ (List Bool))
  (handle Choose ((choose (lambda (resume) (append (resume #t) (resume #f)))))
    (list (choose))))

(define main
  (lambda ()
    (both)
    (unit)))
