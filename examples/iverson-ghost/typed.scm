(import (scheme base) (scheme write) (snail typing) (snail-scheme iverson-typed))

;; The same generic definition specializes to eager kernels or graph builders.
(define data (tensor '(2 2) '(1 2 3 4) 'f32))
(define graph (tensor-gram (symbolic-input 'x)))

(write (immediate-values (tensor-gram data))) (newline)
(write (symbolic->datum graph)) (newline)
(write (immediate-values (evaluate graph (lambda (name) data)))) (newline)

;; A selected specialization is also an ordinary first-class procedure.
(define square-now (inst tensor-square <immediate-tensor>))
(write (immediate-values (square-now data))) (newline)
