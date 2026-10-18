(import
 (lofi base))
;; The first call fixes the parameter's callable type to one argument.
(def invoke
     (lambda (function)
       (begin (function 1) (function 1 2))))
42
