;; The Scheme interpreter: definitions that persist between evaluations,
;; closures, tail calls in constant space, the derived forms, and typed
;; functions bound into an environment.
(import
 (lofi base)
 (lofi io)
 (lofi datum)
 (lofi write)
 (scheme eval))

(define environment (standard-environment))

(: run (-> String Unit ! console mut))
(define (run text)
  (write-line (datum->string (eval-text text environment))))

(run "(define (square x) (* x x)) (square 12)")
(run "(define counter (let ((n 0)) (lambda () (set! n (+ n 1)) n))) (counter) (counter)")
(run "(define (count-up n) (let loop ((i 0)) (if (= i n) i (loop (+ i 1))))) (count-up 100000)")
(run "(let* ((a 1) (b (+ a 1))) (list a b))")
(run "(letrec ((even? (lambda (n) (if (= n 0) #t (odd? (- n 1))))) (odd? (lambda (n) (if (= n 0) #f (even? (- n 1)))))) (even? 1001))")
(run "(define (classify n) (cond ((< n 0) 'negative) ((assv-like n) => car) ((= n 0) 'zero) (else 'positive)))")
(run "(define (assv-like n) (if (= n 7) (list 'lucky) #f)) (map classify (list -1 0 7 9))")
(run "(case (* 2 3) ((2 3 5 7) 'prime) ((1 4 6 8 9) 'composite) (else 'other))")
(run "(list (and 1 2) (and) (or #f 3) (or) (when #f 1) (unless #f 2))")
(run "(do ((i 0 (+ i 1)) (total 0 (+ total i))) ((= i 5) total))")
(run "(define (f . items) items) (f 1 2 3)")
(run "(define (g a b . rest) (list a b rest)) (g 1 2 3 4)")
(run "(define (h) (define x 10) (define (twice) (* 2 x)) (twice)) (h)")
(run "(for-each (lambda (x) (display x) (display \" \")) '(a b c))")
(run "(define value 1) (define (value-later) later) (define later 'defined-after) (value-later)")
(run "(apply + 1 2 '(3 4))")
(run "(let ((or 5)) or)")

;; Typed functions join the environment as procedures.
(: hypotenuse (-> F64 F64 F64))
(define (hypotenuse a b)
  (sqrt (+ (* a a) (* b b))))

(environment-define! environment "hypotenuse" (to-datum hypotenuse))
(run "(hypotenuse 3 4)")
(write-line (string-join (take (reverse (environment-names environment)) 3) " "))
(run "(car '())")
