;; Arithmetic policies for asymmetric operand types. Core numeric operators
;; keep their existing classes; a program opts into these instances lexically.
(define-library (snail shell arithmetic)
  (export
   Add
   Add.Output
   add
   Sub
   Sub.Output
   subtract
   Mul
   Mul.Output
   multiply
   Div
   Div.Output
   divide
   arithmetic-base
   inexact-promotion)
  (import
   (snail core base)
   (snail shell integer)
   (snail shell rational))
  (begin

    ;; ---- Operation contracts ----

    (typeclass (Add e A B)
      (type Output)
      (: add (impl (Fn A B → Output ! e))))

    (typeclass (Sub e A B)
      (type Output)
      (: subtract (impl (Fn A B → Output ! e))))

    (typeclass (Mul e A B)
      (type Output)
      (: multiply (impl (Fn A B → Output ! e))))

    (typeclass (Div e A B)
      (type Output)
      (: divide (impl (Fn A B → Output ! e))))

    ;; ---- Exact arithmetic and equal inexact operands ----

    (define-instance-set arithmetic-base
      (instance (Add (!) Integer Integer)
        (type Output Integer)
        (define add (lambda (a b) (integer-add a b))))
      (instance (Add (!) Integer Rational)
        (type Output Rational)
        (define add (lambda (a b) (rational-add (rational-from-integer a) b))))
      (instance (Add (!) Rational Integer)
        (type Output Rational)
        (define add (lambda (a b) (rational-add a (rational-from-integer b)))))
      (instance (Add (!) Rational Rational)
        (type Output Rational)
        (define add (lambda (a b) (rational-add a b))))
      (instance (Add (!) F64 F64)
        (type Output F64)
        (define add (lambda (a b) (+ a b))))
      (instance (Sub (!) Integer Integer)
        (type Output Integer)
        (define subtract (lambda (a b) (integer-subtract a b))))
      (instance (Sub (!) Integer Rational)
        (type Output Rational)
        (define subtract (lambda (a b) (rational-subtract (rational-from-integer a) b))))
      (instance (Sub (!) Rational Integer)
        (type Output Rational)
        (define subtract (lambda (a b) (rational-subtract a (rational-from-integer b)))))
      (instance (Sub (!) Rational Rational)
        (type Output Rational)
        (define subtract (lambda (a b) (rational-subtract a b))))
      (instance (Sub (!) F64 F64)
        (type Output F64)
        (define subtract (lambda (a b) (- a b))))
      (instance (Mul (!) Integer Integer)
        (type Output Integer)
        (define multiply (lambda (a b) (integer-multiply a b))))
      (instance (Mul (!) Integer Rational)
        (type Output Rational)
        (define multiply (lambda (a b) (rational-multiply (rational-from-integer a) b))))
      (instance (Mul (!) Rational Integer)
        (type Output Rational)
        (define multiply (lambda (a b) (rational-multiply a (rational-from-integer b)))))
      (instance (Mul (!) Rational Rational)
        (type Output Rational)
        (define multiply (lambda (a b) (rational-multiply a b))))
      (instance (Mul (!) F64 F64)
        (type Output F64)
        (define multiply (lambda (a b) (* a b))))
      (instance (Div (!) Integer Integer)
        (type Output Rational)
        (define divide (lambda (a b) (make-rational a b))))
      (instance (Div (!) Integer Rational)
        (type Output Rational)
        (define divide (lambda (a b) (rational-divide (rational-from-integer a) b))))
      (instance (Div (!) Rational Integer)
        (type Output Rational)
        (define divide (lambda (a b) (rational-divide a (rational-from-integer b)))))
      (instance (Div (!) Rational Rational)
        (type Output Rational)
        (define divide (lambda (a b) (rational-divide a b))))
      (instance (Div (!) F64 F64)
        (type Output F64)
        (define divide (lambda (a b) (/ a b)))))

    ;; ---- Explicitly enabled rounding to F64 ----

    (define-instance-set inexact-promotion
      (instance (Add (!) Integer F64)
        (type Output F64)
        (define add (lambda (a b) (+ (integer->f64 a) b))))
      (instance (Add (!) F64 Integer)
        (type Output F64)
        (define add (lambda (a b) (+ a (integer->f64 b)))))
      (instance (Add (!) Rational F64)
        (type Output F64)
        (define add (lambda (a b) (+ (rational->f64 a) b))))
      (instance (Add (!) F64 Rational)
        (type Output F64)
        (define add (lambda (a b) (+ a (rational->f64 b)))))
      (instance (Sub (!) Integer F64)
        (type Output F64)
        (define subtract (lambda (a b) (- (integer->f64 a) b))))
      (instance (Sub (!) F64 Integer)
        (type Output F64)
        (define subtract (lambda (a b) (- a (integer->f64 b)))))
      (instance (Sub (!) Rational F64)
        (type Output F64)
        (define subtract (lambda (a b) (- (rational->f64 a) b))))
      (instance (Sub (!) F64 Rational)
        (type Output F64)
        (define subtract (lambda (a b) (- a (rational->f64 b)))))
      (instance (Mul (!) Integer F64)
        (type Output F64)
        (define multiply (lambda (a b) (* (integer->f64 a) b))))
      (instance (Mul (!) F64 Integer)
        (type Output F64)
        (define multiply (lambda (a b) (* a (integer->f64 b)))))
      (instance (Mul (!) Rational F64)
        (type Output F64)
        (define multiply (lambda (a b) (* (rational->f64 a) b))))
      (instance (Mul (!) F64 Rational)
        (type Output F64)
        (define multiply (lambda (a b) (* a (rational->f64 b)))))
      (instance (Div (!) Integer F64)
        (type Output F64)
        (define divide (lambda (a b) (/ (integer->f64 a) b))))
      (instance (Div (!) F64 Integer)
        (type Output F64)
        (define divide (lambda (a b) (/ a (integer->f64 b)))))
      (instance (Div (!) Rational F64)
        (type Output F64)
        (define divide (lambda (a b) (/ (rational->f64 a) b))))
      (instance (Div (!) F64 Rational)
        (type Output F64)
        (define divide (lambda (a b) (/ a (rational->f64 b))))))))
