(import
 (lofi base)
 (lofi io))

;; Two class parameters, chosen together.
(typeclass (Convert A B)
  (: convert (-> A B)))

(instance (Convert I64 String)
  (define (convert n) (string-append "#" (show n))))

(instance (Convert I64 F64)
  (define (convert n) (i64->f64 n)))

;; A method with a type variable of its own.
(typeclass (Collection C)
  (: collect (All (A) (-> C (-> I64 A) (List A)))))

(struct Range
  ((start I64)
   (end I64)))

(instance (Collection Range)
  (define (collect range f)
    (map f (map (lambda (i) (+ i (Range-start range))) (iota (- (Range-end range) (Range-start range)))))))

;; A generic function whose requirements pass evidence on.
(: describe-all (All (C) (requires (Collection C)) (-> C (List String))))
(define (describe-all collection)
  (collect collection (lambda (n) (ann (convert n) String))))

(write-line (ann (convert 5) String))
(display (* 2.0 (ann (convert 5) F64)))
(newline)
(display (collect (Range 3 6) (lambda (n) (* n n))))
(newline)
(display (describe-all (Range 1 4)))
(newline)
