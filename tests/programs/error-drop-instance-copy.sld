(import
 (snail core base)
 (snail core io))

;; A Drop instance that requires (Copy A) plans its body's drops with A
;; unrestricted, so dropping the pair is free there. Used at a Handle, it
;; would release one handle twice.
(effect log
  ((say (dyn (Fn String → Unit)))))

(struct Handle
  ((name String)))

(instance (Drop (! log) Handle)
  (define drop
    (lambda (handle) (match handle
                       ((Handle name) (say (string-append "released " name)))))))

(struct (Wrapper A)
  ((item A)))

(instance (Drop (! log) (Wrapper A))
  (⊨ (Copy A))
  (define drop
    (lambda (wrapper) (match wrapper
                        ((Wrapper item) (drop (Pair item item)))))))

(define (demo) (→ Unit) (! log)
  (drop (Wrapper (Handle "h"))))

(handle log
    ((say (lambda (text) (write-line text))))
  (demo))
