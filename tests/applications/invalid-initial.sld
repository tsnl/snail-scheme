;; Metadata declares five words but initialization encodes four.
(define-library (tests invalid-initial)
  (export answer)
  (import
   (scheme base)
   (rename (async-boundary) (answer application-entry))
   (only (lofi core) ann -> I32 define-extern))
  (begin
    (define-extern stage "snail.reducer" "write" (-> I32 I32 I32 Unit))
    (define answer
      (ann (lambda (operation a b c)
             (cond ((and (= operation 0) (= a 1)) 5)
                   ((and (= operation 1) (= a 1)) (stage 1 -1 4) (application-entry operation a b c))
                   (else (application-entry operation a b c))))
           (-> I32 I32 I32 I32 I32)))))
