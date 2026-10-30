(import
 (snail core base)
 (snail core io))

;; A type that holds itself at other arguments would need glue at every
;; depth, so dropping one needs an instance.
(struct Handle
  ((name String)))

(instance (Drop (! console) Handle)
  (define (drop handle)
    (match handle
      ((Handle name) (write-line (string-append "released " name))))))

(struct (Nest T)
  ((item T)
   (deeper (Option (Nest (Pair T T))))))

(drop (Nest (Handle "h") (None)))
