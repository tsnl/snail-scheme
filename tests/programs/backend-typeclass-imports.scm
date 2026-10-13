(import (scheme base) (scheme write)
        (rename (snail typing) (define-class class) (define-instance instance) (: signature))
        (prefix (testing typeclasses) a:)
        (rename (testing typeclasses) (render display-item) (Render Rendering)))

(define (check expected actual)
  (unless (equal? expected actual) (error "class import mismatch" expected actual)))

(instance (Rendering String) (display-item (lambda (value) value)))
(check "librarylibrary" (a:render-twice (a:item "library")))
(check "texttext" (a:render-twice "text"))
(check "nominal" (display-item (a:item "nominal")))

;; Identical spellings introduced by separate macros still have distinct types.
(define-syntax make-renderer
  (syntax-rules ()
    ((_ method instance-type value)
     (begin (class (Hidden T) (signature method (-> T String)))
            (instance (Hidden instance-type) (method (lambda (x) value)))))))
(make-renderer first String "first")
(make-renderer second String "second")
(check "first" (first "value"))
(check "second" (second "value"))
(display "typeclass import checks passed\n")
