(import
 (snail core base)
 (snail core io))

;; A Clone instance that requires (Copy A) may share its item between
;; the halves. Used at a Handle, the two halves would release one handle
;; twice.
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

(instance (Clone (!) (Wrapper A))
  (requires (Copy A))
  (define (clone wrapper)
    (match wrapper
      ((Wrapper item) (Pair (Wrapper item) (Wrapper item))))))

(: demo (-> Unit ! log))
(define (demo)
  (match (clone (Wrapper (Handle "h")))
    ((Pair a b) (drop a) (drop b))))

(handle log
    ((say (lambda (text) (write-line text))))
  (demo))
