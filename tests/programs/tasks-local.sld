(import
 (snail-core base)
 (snail-core io)
 (snail-core task))
(let ((cell (ref (ann 0 I64))))
  (dispatch-local
   (once (lambda ()
           (ref-set! cell 42)
           (yield)
           (display (ref-get cell))
           (newline)))))
