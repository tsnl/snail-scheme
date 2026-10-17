(define-library (tests invalid-candidate)
  (export answer)
  (import
   (scheme base)
   (siegework game)
   (only (lofi core) ann -> I32 define-extern))
  (begin
    (define-extern stage "snail.reducer" "write" (-> I32 I32 I32 Unit))
    (define answer (ann (lambda (operation a b c)
                          (if (= operation 10) (begin (stage 1 3 0) 1)
                              (application-entry operation a b c))) (-> I32 I32 I32 I32 I32)))))
