(import
 (snail core base)
 (snail core io))

(typeclass (Add e A B)
  (type Output)
  (declare (add (left A) (right B)) (→ Output) (! e)))

(instance (Add (!) I64 F64)
  (type Output F64)
  (define (add (a I64) (b F64)) (→ F64)
    (+ (i64->f64 a) b)))

(instance (Add (!) I64 I64)
  (type Output I64)
  (define (add (a I64) (b I64)) (→ I64)
    (+ a b)))

(define (sum (a A) (b B)) (→ (Add.Output e A B)) (! e) (∀ (A B e)) (⊨ (Add e A B)) (add a b))

(define (twice (a A))
  (→ A)
  (! e)
  (∀ (A e))
  (⊨ (Add e A A (type Output A)))
  (add a a))

;; An output of an earlier prerequisite becomes a later prerequisite's input.
(record (Box A)
  ((value A)))

(typeclass (Extract T)
  (type Output)
  (declare (extract (value T)) (→ Output)))

(instance (Extract (Box A))
  (type Output A)
  (define (extract (value (Box A))) (→ A)
    (match value ((Box value) value))))

(instance (Add (! e) (Box A) B)
  (⊨ (Extract (Box A)) (Add e (Extract.Output (Box A)) B))
  (type Output (Add.Output e (Extract.Output (Box A)) B))
  (define (add (a (Box A)) (b B)) (→ (Add.Output e (Extract.Output (Box A)) B)) (! e)
    (add (extract a) b)))

;; Recursion that makes its input smaller is permitted.
(typeclass (Flatten A)
  (type Output)
  (declare (flatten (value A)) (→ Output)))

(instance (Flatten I64)
  (type Output I64)
  (define (flatten (value I64)) (→ I64)
    value))

(instance (Flatten (Box A))
  (⊨ (Flatten A))
  (type Output (Flatten.Output A))
  (define (flatten (value (Box A))) (→ (Flatten.Output A))
    (match value ((Box inner) (flatten inner)))))

;; Class variables introduced by a macro retain their lexical marks.
(define-syntax define-identity-class
  (syntax-rules ()
    ((_ class method)
     (typeclass (class A)
       (type Output)
       (declare (method (value A)) (→ Output))))))

(define-identity-class Identity identity)

(instance (Identity I64)
  (type Output I64)
  (define (identity (value I64)) (→ I64)
    value))

(define (main) (→ Unit) (! output-port)

  (display (sum (ann 1 I64) 2.5))
  (newline)
  (display (twice (ann 7 I64)))
  (newline)
  (display (sum (new Box (value (ann 4 I64))) 0.5))
  (newline)
  (display (flatten (new Box (value (new Box (value (ann 9 I64)))))))
  (newline)
  (display (identity (ann 11 I64)))
  (newline)
  (unit))
