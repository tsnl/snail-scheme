;; Adversarial bridge fixture: writes and effects must remain staged on a trap.
(define-library (tests trap)
  (export answer)
  (import
   (scheme base)
   (siegework game)
   (only (lofi core) ann -> I32 define-extern)
   (only (lofi base) unreachable))
  (begin
    (define-extern stage "snail.reducer" "write" (-> I32 I32 I32 Unit))
    (define-extern effect "snail.reducer" "command" (-> I32 I32 I32 I32 Unit))
    (define answer (ann (lambda (operation a b c)
                          (if (= operation 2)
                              (begin (stage 1 3 0) (effect 1 0 0 0) (unreachable))
                              (application-entry operation a b c))) (-> I32 I32 I32 I32 I32)))))
