;; An encoded replacement with the wrong schema must never reach persistence.
(define-library (tests invalid-state)
  (export answer)
  (import
   (scheme base)
   (rename (async-boundary) (answer application-entry))
   (only (lofi core) ann -> I32 define-extern))
  (begin
    (define-extern stage "snail.reducer" "write" (-> I32 I32 I32 Unit))
    (define answer
      (ann (lambda (operation a b c)
             (if (= operation 2) (begin (stage 1 0 99) 1)
                 (application-entry operation a b c)))
           (-> I32 I32 I32 I32 I32)))))
