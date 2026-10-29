(import
 (snail core base)
 (snail core io))

;; A labelled box says so when it is released, then drops what it holds:
;; its instance performs `log`, and the row `e` of its requirement, which
;; is whatever dropping the item performs. The book's ownership chapter
;; includes the text between ANCHOR and ANCHOR_END.
(effect log
  ((say (-> String Unit))))

(effect audit
  ((note (-> String Unit))))

(struct Handle
  ((name String)))

(instance (Drop (! audit) Handle)
  (define (drop handle)
    (match handle
      ((Handle name) (note (string-append "closed " name))))))

;; ANCHOR: labelled
(struct (Labelled A)
  ((label String)
   (item A)))

(instance (Drop (! log e) (Labelled A))
  (requires (Drop e A))
  (define (drop labelled)
    (match labelled
      ((Labelled label item)
       (say (string-append "releasing " label))
       (drop item)))))
;; ANCHOR_END: labelled

;; A generic drop of a labelled box performs `log` and its item's row.
(: release (All (A e) (requires (Drop e A)) (-> (Labelled A) Unit ! log e)))
(define (release labelled)
  (drop labelled))

(: demo (-> Unit ! log audit))
(define (demo)
  (drop (Labelled "one" (Handle "a")))
  (drop (Labelled "outer" (Labelled "inner" (Handle "b"))))
  ;; An unrestricted item drops at no cost, and performs nothing.
  (drop (Labelled "number" 7))
  ;; Glue reaches the instance through a pair.
  (drop (Pair (Labelled "left" (Handle "c")) (Handle "d")))
  (release (Labelled "generic" (Handle "e")))
  (say "done"))

(handle log
    ((say (lambda (text) (write-line text))))
  (handle audit
      ((note (lambda (text) (write-line (string-append "  " text)))))
    (demo)))
