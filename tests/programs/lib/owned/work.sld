(define-library (owned work)
  (export message run)
  (import
   (snail-core base)
   (snail-core io))
  (begin
    (: message (-> String (Once (-> Unit ! console))))
    (define (message text) (once (lambda () (write-line text))))

    (: run (-> (Once (-> Unit ! console)) Unit ! console))
    (define (run work) (call-once work))))
