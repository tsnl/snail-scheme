;; Candidate decoding accepts the initial economy but rejects a later purchase.
(define-library (tests current-state)
  (export answer)
  (import
   (scheme base)
   (siegework game)
   (siegework model)
   (application bridge)
   (application serialization)
   (only (lofi core) ann -> I32 define-extern))
  (begin
    (define-extern snapshot-read "snail.reducer" "read" (-> I32 I32 I32))
    (define answer
      (ann (lambda (operation a b c)
             (if (and (= operation 10) (not (= (snapshot-read 1 0) 0))
                      (not (= (world-credits (ann (decode-snapshot (read-snapshot 1)) World)) 110)))
                 0 (application-entry operation a b c)))
           (-> I32 I32 I32 I32 I32)))))
