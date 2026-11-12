(import
 (snail core base)
 (snail core io))

;; Run with SNAIL_GC_STRESS=1 as well: every allocation then collects. These
;; values cross parameter, pending operand, loop and captured-environment roots.
(struct Box
  ((value I64)
   (label String)))

(: fresh (impl (Fn I64 -> Box)))
(define (fresh value)
  (Box value (show value)))

(: parameter (impl (Fn Box -> I64)))
(define (parameter held)
  (let ((noise (vector-generate 50 (lambda (index) (show index)))))
    (+ (::value held) (vector-length noise))))

(: operands (impl (Fn Box Box -> String)))
(define (operands left right)
  (string-append (::label left) ":" (::label right)))

(: rotate (impl (Fn Box Box I64 -> String)))
(define (rotate previous current remaining)
  (if (= remaining 0)
      (operands previous current)
      (rotate current (fresh (+ (::value current) 1)) (- remaining 1))))

(: capture (impl (Fn Box -> (dyn (Fn I64 -> String)))))
(define (capture held)
  (lambda (value) (operands held (fresh value))))

(write-line (show (parameter (fresh 17))))
(write-line (operands (fresh 10) (fresh 20)))
(write-line (rotate (fresh 0) (fresh 1) 199))
(write-line ((capture (fresh 7)) 11))

;; The array initializer remains live while allocating the array; elements
;; survive later allocations in generate's loop, including nonfinal elements.
(let ((words (vector-generate 80 (lambda (index) (show index)))))
  (write-line (string-append (vector-ref words 3) ":" (vector-ref words 77))))
