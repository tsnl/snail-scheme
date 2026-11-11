(import
 (snail core base)
 (snail core io))
(define (annotations (value I64)) (→ I64) (+ value 1))
(define result (annotations 3))
(write-line (show result))
(define define (→ I64) (annotations (doc "A value named define.")) 7)
(write-line (show define))
