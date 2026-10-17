(import
 (lofi base))
(def Point (datatype ()
             (point
              (x I64 point-x))))
(def outer
     (point 8))
(def local
     (lambda ()
       (begin
         (def Point (datatype ()
                      (point
                       (x F64 point-x))))
         (f64->i64 (point-x (point 7.5))))))
(+ (point-x outer) (local))
