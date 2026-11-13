(import
 (snail core base)
 (snail core io))

;; An instance of an ordinary class may require a drop of its variable,
;; with the row the class's method allows. Each use drops the type it
;; gives A as any drop does: through its instance, its glue, or for
;; nothing, and charges what that performs to the requirement's row.
(effect log
  ((say (Fn String → Unit))))

(struct Handle
  ((name String)))

(instance (Drop (! log) Handle)
  (define drop
    (lambda (handle) (match handle
                       ((Handle name) (say (string-append "released " name)))))))

(typeclass (Release T)
  (declare (release (value T)) (→ Unit) (! log)))

(instance (Release (Option A))
  (⊨ (Drop (! log) A))
  (define release
    (lambda (option) (match option
                       ((Some item) (drop item))
                       ((None) (say "nothing to release"))))))

;; A definition that requires (Copy A) releases an A for nothing.
(define (release-copy (value A)) (→ Unit) (! log) (∀ (A)) (⊨ (Copy A) (Drop (! log) A))
  (release (Some value)))

(define (demo) (→ Unit) (! log)
  (release (Some (Handle "h")))
  (release (Some (Pair (Handle "p") (Handle "q"))))
  (release (Some 3))
  (release-copy "text")
  (release (ann (None) (Option Handle))))

(define main
  (lambda ()
    (handle log
        ((say (lambda (text) (write-line text))))
      (demo))
    (unit)))
