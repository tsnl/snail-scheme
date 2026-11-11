(import
 (snail core base))

;; A Drop instance made the handle linear, so its library decides what a
;; copy is, and it has said nothing.
(struct Handle
  ((id I64)))

(instance (Drop (!) Handle)
  (define drop
    (lambda (handle) (match handle
                       ((Handle _) (unit))))))

(define copies (→ (Pair Handle Handle))
  (clone (Handle 1)))
