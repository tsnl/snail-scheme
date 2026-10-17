;; A compatible generation whose view fails only after a committed flag changes.
(define-library (tests async-view)
  (export answer)
  (import
   (scheme base)
   (rename (async-boundary) (answer base-answer))
   (only (lofi core) ann -> I32 define-extern)
   (only (lofi base) unreachable))
  (begin
    (define-extern read "snail.reducer" "read" (-> I32 I32 I32))
    (define answer
      (ann (lambda (operation a b c)
             (if (and (= operation 4) (= (read 1 2) 1))
                 (unreachable)
                 (base-answer operation a b c)))
           (-> I32 I32 I32 I32 I32)))))
