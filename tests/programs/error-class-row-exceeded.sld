(import
 (snail core base)
 (snail core io))

;; A total function may not read from a store whose instance prints.
(typeclass (Store e S)
  (: fetch-object (impl (Fn S String -> String ! e))))

(struct Directory
  ((root String)))

(instance (Store (! console) Directory)
  (define (fetch-object directory name)
    (write-line name)
    name))

(: quiet (impl (Fn Directory String -> String)))
(define (quiet directory name)
  (fetch-object directory name))
