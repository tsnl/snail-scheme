(import
 (snail core base))

;; Dropping a labelled handle performs the handle's row too, which this
;; signature does not allow.
(effect audit
  ((note (-> String Unit))))

(struct Handle
  ((name String)))

(instance (Drop (! audit) Handle)
  (define (drop handle)
    (match handle
      ((Handle name) (note name)))))

(struct (Labelled A)
  ((label String)
   (item A)))

(instance (Drop (! e) (Labelled A))
  (requires (Drop e A))
  (define (drop labelled)
    (match labelled
      ((Labelled _ item) (drop item)))))

(: release (-> (Labelled Handle) Unit))
(define (release labelled)
  (drop labelled))
