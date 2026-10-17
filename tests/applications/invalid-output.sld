;; A tiny hostile producer isolates output materialization from game rules.
;; Its transition stages a valid new marker followed by an invalid Unicode scalar.
(define-library (tests invalid-output)
  (export answer)
  (import
   (scheme base)
   (only (lofi core) ann -> I32 define-extern))
  (begin
    (define-extern stage "snail.reducer" "write" (-> I32 I32 I32 Unit))
    (define-extern label "snail.reducer" "label" (-> I32 I32 Unit))
    (define answer
      (ann (lambda (operation a b c)
             (cond ((= operation 0) (if (= a 1) 2 1))
                   ((= operation 1) (stage a 0 1) 1)
                   ((= operation 2)
                    (stage 1 1 1)
                    (label -1 1)
                    (label 0 1114112)
                    1)
                   (else 1)))
           (-> I32 I32 I32 I32 I32)))))
