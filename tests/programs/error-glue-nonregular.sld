(import
 (snail core base)
 (snail core io))

;; A type that holds itself at other arguments would need glue at every
;; depth, so dropping one needs an instance.
(record Handle
  ((name String)))

(instance (Drop (! output-port) Handle)
  (define (drop (handle Handle)) (→ Unit) (! output-port)
    (match handle
      ((Handle name) (write-line (string-append "released " name))))))

(record (Nest T)
  ((item T)
   (deeper (Option (Nest (Pair T T))))))

(define (main) (→ Unit) (! output-port)

  (drop (new Nest (item (new Handle (name "h"))) (deeper (None))))
  (unit))
