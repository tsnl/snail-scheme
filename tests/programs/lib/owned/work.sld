(define-library (owned work)
  (export message run)
  (import
   (lofi base)
   (lofi io))
  (begin
    (: message (-> String (Once (-> Unit ! console))))
    (define (message text) (once (lambda () (write-line text))))

    (: run (-> (Once (-> Unit ! console)) Unit ! console))
    (define (run work) (call-once work))))
