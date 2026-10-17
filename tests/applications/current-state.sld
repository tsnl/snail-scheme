;; Candidate decoding accepts the initial economy but rejects a later purchase.
(define-library (tests current-state)
  (export answer)
  (import (scheme base) (siegework game) (only (lofi core) ann -> I32 define-extern))
  (begin
    (define-extern snapshot-read "snail.reducer" "read" (-> I32 I32 I32))
    (define answer
      (ann (lambda (operation a b c)
             (if (and (= operation 10) (not (= (snapshot-read 1 0) 0))
                      (not (= (snapshot-read 1 3) 160)))
                 0 (application-entry operation a b c)))
           (-> I32 I32 I32 I32 I32)))))
