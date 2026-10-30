(import
 (snail core base)
 (snail core io))

;; An instance's drop requirement allows only its row: releasing a Handle
;; performs `log`, which `(Drop (!) A)` does not allow.
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
  (requires (Drop (!) A))
  (define (release option)
    (match option
      ((Some item) (drop item))
      ((None) (unit)))))

(: demo (-> Unit ! log))
(define (demo)
  (release (Some (Handle "h"))))

(handle log
    ((say (lambda (text) (write-line text))))
  (demo))
