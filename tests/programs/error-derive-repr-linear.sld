(import
 (snail core base)
 (snail core io))

(struct Handle
  ((id I64))
  (deriving Repr))

;; The later Drop declaration makes this an owner, even with scalar fields.
(instance (Drop (! output-port) Handle)
  (define (drop (handle Handle)) (→ Unit) (! output-port)
    (match handle ((Handle id) (display id)))))

(define main
  (lambda ()
    (write (Handle 1))
    (unit)))
