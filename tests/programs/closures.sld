(import
 (snail core base)
 (snail core io))

(define (adder (n I64)) (→ (Fn I64 → I64))
  (lambda (x) (+ x n)))

(define (compose (f (Fn B → C)) (g (Fn A → B))) (→ (Fn A → C)) (∀ (A B C))
  (lambda (x) (f (g x))))

(define (count-down (n I64)) (→ I64)
  (let loop ((i n) (total 0))
    (if (= i 0) total (loop (- i 1) (+ total i)))))

(define (add5) (→ (Fn I64 → I64)) (adder 5))

(define (main (out OutputPort)) (→ Unit)
  (display out ((add5) 10))
  (newline out)
  (display out ((compose (add5) (adder 100)) 1))
  (newline out)
  (display out (count-down 1000000))
  (newline out)
  (let ((base 7))
    (define scale (lambda (x) (* x base)))
    (define twice (lambda (f x) (f (f x))))
    (display out (twice scale 2))
    (newline out))
  (display out (fold-left + 0 (map (lambda (x) (* x x)) (list 1 2 3 4))))
  (newline out)
  (display out (length (filter (lambda (x) (> x 2)) (iota 10))))
  (newline out)
  (unit))
