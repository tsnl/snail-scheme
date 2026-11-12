(import
 (snail core base))

;; Dropping a labelled handle performs the handle's row too, which this
;; signature does not allow.
(effect audit
  ((note (Fn String → Unit))))

(struct Handle
  ((name String)))

(instance (Drop (! audit) Handle)
  (define drop
    (lambda (handle) (match handle
                       ((Handle name) (note name))))))

(struct (Labelled A)
  ((label String)
   (item A)))

(instance (Drop (! e) (Labelled A))
  (⊨ (Drop e A))
  (define drop
    (lambda (labelled) (match labelled
                         ((Labelled _ item) (drop item))))))

(define (release (labelled (Labelled Handle))) (→ Unit)
  (drop labelled))
