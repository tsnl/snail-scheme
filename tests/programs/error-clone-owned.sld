(import
 (snail core base))

;; A Drop instance made the handle linear, so its library decides what a
;; copy is, and it has said nothing.
(struct Handle
  ((id I64)))

(instance (Drop (!) Handle)
  (define (drop handle)
    (match handle
      ((Handle _) (unit)))))

(: copies (Pair Handle Handle))
(define copies
  (clone (Handle 1)))
