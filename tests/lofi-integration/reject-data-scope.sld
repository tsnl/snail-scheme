(import
 (lofi base))
(def Box (datatype ()
           (box
            (value I64 unbox))))
(def outer
     (box 8))
;; A library begin splices; use an expression body to test local rejection.
((lambda ()
   (begin
     (begin (def Box (datatype ()
                       (box
                        (value I64 unbox)))) (unbox outer)))))
