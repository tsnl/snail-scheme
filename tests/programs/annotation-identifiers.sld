(import
 (snail core base)
 (prefix (only (snail core base) define) core:)
 (snail core io))

(define (annotations (value I64)) (→ I64) (+ value 1))

(define result (annotations 3))

(define define (→ I64) (annotations (doc "A value named define.")) 7)

(core:define main
             (lambda ()
               (write-line (show result))
               (write-line (show define))
               (unit)))
