;; Same protocol and state, observably different client reducer behavior.
(define-library (tests compatible)
  (export answer)
  (import
   (scheme base)
   (siegework game)
   (only (lofi core) ann -> I32))
  (begin
    (define answer
      (ann (lambda (operation a b c)
             (if (and (= operation 3) (= a 2))
                 (application-entry operation a (+ b 1) c)
                 (application-entry operation a b c)))
           (-> I32 I32 I32 I32 I32)))))
