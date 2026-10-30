(import
 (snail core base)
 (snail core io))

;; An instance of an ordinary class may require a drop of its variable,
;; with the row the class's method allows. Each use drops the type it
;; gives A as any drop does: through its instance, its glue, or for
;; nothing, and charges what that performs to the requirement's row.
(effect log
  ((say (-> String Unit))))

(struct Handle
  ((name String)))

(instance (Drop (! log) Handle)
  (define (drop handle)
    (match handle
      ((Handle name) (say (string-append "released " name))))))

(typeclass (Release T)
  (: release (-> T Unit ! log)))

(instance (Release (Option A))
  (requires (Drop (! log) A))
  (define (release option)
    (match option
      ((Some item) (drop item))
      ((None) (say "nothing to release")))))

;; A definition that requires (Copy A) releases an A for nothing.
(: release-copy (All (A) (requires (Copy A)) (-> A Unit ! log)))
(define (release-copy value)
  (release (Some value)))

(: demo (-> Unit ! log))
(define (demo)
  (release (Some (Handle "h")))
  (release (Some (Pair (Handle "p") (Handle "q"))))
  (release (Some 3))
  (release-copy "text")
  (release (ann (None) (Option Handle))))

(handle log
    ((say (lambda (text) (write-line text))))
  (demo))
