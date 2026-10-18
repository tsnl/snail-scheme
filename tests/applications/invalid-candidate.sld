;; A tiny candidate that writes during read-only validation.
(define-library (tests invalid-candidate)
  (export answer)
  (import
   (scheme base)
   (rename (async-boundary) (answer application-entry))
   (only (lofi core) ann -> I32 define-extern))
  (begin
    (define-extern stage "snail.reducer" "write" (-> I32 I32 I32 Unit))
    (define answer
      (ann (lambda (operation a b c)
             (if (= operation 10) (begin (stage 1 1 0) 1)
                 (application-entry operation a b c)))
           (-> I32 I32 I32 I32 I32)))))
