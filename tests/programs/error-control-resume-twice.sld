(import
 (snail core base))

;; `resume` is one-shot: an implementation may call it at most once.
(effect Choose
  ((ctl choose (-> Bool))))

(: both (-> (List Bool)))
(define (both)
  (handle Choose ((choose (lambda (resume) (append (resume #t) (resume #f)))))
    (list (choose))))

(both)
