(import
 (snail core base))

;; `resume` is linear: an implementation calls it, or drops it, exactly once.
(effect Choose
  ((ctl choose (-> Bool))))

(: both (-> (List Bool)))
(define (both)
  (handle Choose ((choose (lambda (resume) (append (resume #t) (resume #f)))))
    (list (choose))))

(both)
