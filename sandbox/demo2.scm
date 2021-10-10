; Without macros, only a limited subset of Scheme is supported by the interpreter.
; Here are some expressions in this subset.

; applying 'or2' to '#t' and '#f'-- expect '#f'
((lambda (x y) (if x x y)) #t #f)
