(define fibonacci
  (lambda (n)
    (if (or (= n 0) (= n 1))
      n
      (+ 
        (fibonacci (- n 1))
        (fibonacci (- n 2))))))
  
(display (fibonacci 30))
(display #\newline)