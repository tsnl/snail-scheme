(import
 (lofi core)
 (lofi base))

(def trace (ref 0))
(def stamp
     (lambda (digit)
       (begin
         (ref-set! trace (+ (* (ref-get trace) 10) digit))
         (lambda (value) value))))
(typeclass Identity (T)
           (: first (-> T T))
           (: second (-> T T)))
(instance identity-i32 (Identity I32)
          (first (stamp 1))
          (second (stamp 2)))
(ref-get trace)
