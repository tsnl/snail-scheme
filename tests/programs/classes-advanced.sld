(import
 (snail core base)
 (snail core io))

;; Two class parameters, chosen together.
(typeclass (Convert A B)
  (: convert (Fn A → B)))

(instance (Convert I64 String)
  (define convert (lambda (n) (string-append "#" (show n)))))

(instance (Convert I64 F64)
  (define convert (lambda (n) (i64->f64 n))))

;; A method with a type variable of its own.
(typeclass (Collection C)
  (: collect (∀ (A) (Fn C (Fn I64 → A) → (List A)))))

(struct Range
  ((start I64)
   (end I64)))

(instance (Collection Range)
  (define collect
    (lambda (range f) (map f
                           (map (lambda (i) (+ i (● range start)))
                                (iota (- (● range end) (● range start))))))))

;; A generic function whose requirements pass evidence on.
(define (describe-all (collection C)) (→ (List String)) (∀ C) (⊨ (Collection C))
  (collect collection (lambda (n) (ann (convert n) String))))

(write-line (ann (convert 5) String))
(display (* 2.0 (ann (convert 5) F64)))
(newline)
(write (collect (Range 3 6) (lambda (n) (* n n))))
(newline)
(write (describe-all (Range 1 4)))
(newline)
