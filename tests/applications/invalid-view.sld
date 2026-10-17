(define-library (tests invalid-view)
  (export answer)
  (import
   (scheme base)
   (siegework game)
   (only (lofi core) ann -> I32)
   (only (lofi base) unreachable))
  (begin
    (define answer
      (ann (lambda (operation a b c)
             (if (= operation 4) (unreachable)
                 (application-entry operation a b c)))
           (-> I32 I32 I32 I32 I32)))))
