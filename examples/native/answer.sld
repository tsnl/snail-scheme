(define-library (example answer)
  (export answer)
  (begin
    (def answer (-> I32) (lambda () 42))))
