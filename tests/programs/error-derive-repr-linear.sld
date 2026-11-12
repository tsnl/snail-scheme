(import
 (snail core base)
 (snail core io))

(struct Handle
  ((id I64))
  (deriving Repr))

;; The later Drop declaration makes this an owner, even with scalar fields.
(instance (Drop (! output-port) Handle)
  (define drop (lambda (handle) (match handle ((Handle id) (display id))))))

(write (Handle 1))
