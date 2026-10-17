(define-library (tests invalid-initial)
  (export answer)
  (import (scheme base) (siegework game) (only (lofi core) ann -> I32))
  (begin
    (define answer
      (ann (lambda (operation a b c)
             (if (and (= operation 0) (= a 1)) 191
                 (application-entry operation a b c)))
           (-> I32 I32 I32 I32 I32)))))
