(import
 (snail core base)
 (snail core io))

;; An instance's drop requirement allows only its row: releasing a Handle
;; performs `log`, which `(Drop (!) A)` does not allow.
(effect log
  ((say (Fn String → Unit))))

(struct Handle
  ((name String)))

(instance (Drop (! log) Handle)
  (define drop
    (lambda (handle) (match handle
                       ((Handle name) (say (string-append "released " name)))))))

(typeclass (Release T)
  (: release (Fn T → Unit ! log)))

(instance (Release (Option A))
  (⊨ (Drop (!) A))
  (define release
    (lambda (option) (match option
                       ((Some item) (drop item))
                       ((None) (unit))))))

(define (demo) (→ Unit) (! log)
  (release (Some (Handle "h"))))

(handle log
    ((say (lambda (text) (write-line text))))
  (demo))
