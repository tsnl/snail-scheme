(import
 (snail core base)
 (snail core io))

;; A labelled box says so when it is released, then drops what it holds:
;; its instance performs `log`, and the row `e` of its requirement, which
;; is whatever dropping the item performs. The book's ownership chapter
;; includes the text between ANCHOR and ANCHOR_END.
(effect log
  ((say (Fn String → Unit))))

(effect audit
  ((note (Fn String → Unit))))

(struct Handle
  ((name String)))

(instance (Drop (! audit) Handle)
  (define drop
    (lambda (handle) (match handle
                       ((Handle name) (note (string-append "closed " name)))))))

;; ANCHOR: labelled
(struct (Labelled A)
  ((label String)
   (item A)))

(instance (Drop (! log e) (Labelled A))
  (⊨ (Drop e A))
  (define drop
    (lambda (labelled) (match labelled
                         ((Labelled label item)
                          (say (string-append "releasing " label))
                          (drop item))))))

;; ANCHOR_END: labelled

;; A generic drop of a labelled box performs `log` and its item's row.
(define (release (labelled (Labelled A))) (→ Unit) (! log e) (∀ A e) (⊨ (Drop e A))
  (drop labelled))

(define (demo) (→ Unit) (! log audit)
  (drop (Labelled "one" (Handle "a")))
  (drop (Labelled "outer" (Labelled "inner" (Handle "b"))))
  ;; An unrestricted item drops at no cost, and performs nothing.
  (drop (Labelled "number" 7))
  ;; Glue reaches the instance through a pair.
  (drop (Pair (Labelled "left" (Handle "c")) (Handle "d")))
  (release (Labelled "generic" (Handle "e")))
  (say "done"))

(define main
  (lambda ()
    (handle log
        ((say (lambda (text) (write-line text))))
      (handle audit
          ((note (lambda (text) (write-line (string-append "  " text)))))
        (demo)))
    (unit)))
