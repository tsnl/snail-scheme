(define-library (tests reject-state)
  (export answer)
  (import
   (scheme base)
   (application reducer)
   (only (lofi core) ann -> I32))
  (begin
    (application counter (state I32 1) 0
                 (wrong (state) (no-effects #t)))
    (define answer (ann (lambda () 0) (-> I32)))))
