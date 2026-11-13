;; A deliberate exit flushes pending output and adds no panic prefix.
(import
 (snail core base)
 (snail core io))

(define (main) (→ Unit) (! mut output-port)
  (write-string "flushed")
  (write-error "stderr\n")
  (exit 0))
