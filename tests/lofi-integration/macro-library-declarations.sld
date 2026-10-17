(import
 (lofi core)
 (only (lofi primitive) vector-ref)
 (macro generated-machine))
(let private-increment (lambda (value) 7))
(let private-step (lambda (value) 9))
(counter-value ((vector-ref commands (ann 0 I64)) (make-counter 41)))
