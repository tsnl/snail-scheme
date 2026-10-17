(import
 (scheme base))
(let loop ((n 6) (result 0)) (if (= n 0) result (loop (- n 1) (+ result 7))))
