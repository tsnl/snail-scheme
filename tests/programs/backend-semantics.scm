(import (scheme base) (scheme write) (scheme time))

(define (check expected actual)
  (if (not (equal? expected actual)) (error "backend mismatch" expected actual)))

;; Grandchildren must carry a cell even when their parent never reads it.
(define (counter n)
  (lambda () (lambda () (set! n (+ n 1)) n)))
(define parent (counter 40))
(define a (parent))
(define b (parent))
(check '(41 42 43) (list (a) (b) (a)))

;; Old closures observe later assignments to the same global slot.
(define global 1)
(define (get-global) global)
(set! global 9)
(check 9 (get-global))

;; Both cells exist before either mutually recursive initializer runs.
(check #t
       (letrec ((even (lambda (n) (if (= n 0) #t (odd (- n 1)))))
                (odd (lambda (n) (if (= n 0) #f (even (- n 1))))))
         (even 10000)))

;; Pending arguments remain rooted while another argument calls and allocates.
(check '(1 (2 3) 4) (list 1 (map (lambda (x) (+ x 1)) '(1 2)) 4))
(check '(1 2 3 4) (apply (lambda (x . rest) (cons x rest)) 1 2 '(3 4)))
(check '(a b c) (call-with-values (lambda () (values 'a 'b 'c)) list))
(check '() (call-with-values (lambda () (values)) list))
(check '(5 6) (call-with-values (lambda () (apply values '(5 6))) list))
(check '(1 2) (call-with-values
                  (lambda () (call-with-values (lambda () (values 1 2)) values)) list))

;; The chosen evaluation order is arguments left-to-right, then operator.
(define order '())
(define (note x) (set! order (cons x order)) x)
((begin (note 'operator) list) (note 'first) (note 'second))
(check '(operator second first) order)
(check '#(1 (2 . 3) "héλ😀") '#(1 (2 . 3) "héλ😀"))
(check #u8(0 127 255) #u8(0 127 255))
(check 5.5 (+ 2.5 3))
(check 4294967296 (+ 4294967295 1))
(check #t (>= (current-jiffy) 0))
(check 1000000000 (jiffies-per-second))
(display "backend checks passed\n")
