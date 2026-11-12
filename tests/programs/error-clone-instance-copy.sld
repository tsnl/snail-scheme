(import
 (snail core base)
 (snail core io))

;; A Clone instance that requires (Copy A) may share its item between
;; the halves. Used at a Handle, the two halves would release one handle
;; twice.
(effect log
  ((say (Fn String → Unit))))

(struct Handle
  ((name String)))

(instance (Drop (! log) Handle)
  (define drop
    (lambda (handle) (match handle
                       ((Handle name) (say (string-append "released " name)))))))

(struct (Wrapper A)
  ((item A)))

(instance (Clone (!) (Wrapper A))
  (⊨ (Copy A))
  (define clone
    (lambda (wrapper) (match wrapper
                        ((Wrapper item) (Pair (Wrapper item) (Wrapper item)))))))

(define (demo) (→ Unit) (! log)
  (match (clone (Wrapper (Handle "h")))
    ((Pair a b) (drop a) (drop b))))

(define main
  (lambda ()
    (handle log
        ((say (lambda (text) (write-line text))))
      (demo))
    (unit)))
