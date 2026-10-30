(import
 (snail core base)
 (snail core io))

;; A Drop instance that requires (Copy A) plans its body's drops with A
;; unrestricted, so dropping the pair is free there. Used at a Handle, it
;; would release one handle twice.
(effect log
  ((say (-> String Unit))))

(struct Handle
  ((name String)))

(instance (Drop (! log) Handle)
  (define (drop handle)
    (match handle
      ((Handle name) (say (string-append "released " name))))))

(struct (Wrapper A)
  ((item A)))

(instance (Drop (! log) (Wrapper A))
  (requires (Copy A))
  (define (drop wrapper)
    (match wrapper
      ((Wrapper item) (drop (Pair item item))))))

(: demo (-> Unit ! log))
(define (demo)
  (drop (Wrapper (Handle "h"))))

(handle log
    ((say (lambda (text) (write-line text))))
  (demo))
