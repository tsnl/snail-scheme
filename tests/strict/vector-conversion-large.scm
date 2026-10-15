(import (snail strict))
(define values
  (list->vector
   (let loop ((index 99999) (result '()))
     (if (< index 0) result
         (loop (- index 1) (cons index result))))))
(define joined (vector-append (vector -1) values (vector 100000)))
(if (and (= (vector-length values) 100000)
         (= (vector-ref values 0) 0)
         (= (vector-ref values 99999) 99999)
         (= (vector-length joined) 100002)
         (= (vector-ref joined 0) -1)
         (= (vector-ref joined 1) 0)
         (= (vector-ref joined 100000) 99999)
         (= (vector-ref joined 100001) 100000))
    42 (unreachable))
