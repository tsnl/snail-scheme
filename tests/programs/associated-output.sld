(import
 (snail core base)
 (snail core io))

(typeclass (Add e A B)
  (type Output)
  (: add (-> A B Output ! e)))

(instance (Add (!) I64 F64)
  (type Output F64)
  (define (add a b) (+ (i64->f64 a) b)))

(instance (Add (!) I64 I64)
  (type Output I64)
  (define (add a b) (+ a b)))

(: sum
   (All (A B e)
        (requires (Add e A B))
        (-> A B (Add.Output e A B) ! e)))
(define (sum a b) (add a b))

(: twice
   (All (A e)
        (requires (Copy A) (Add e A A (type Output A)))
        (-> A A ! e)))
(define (twice a) (add a a))

(display (sum (ann 1 I64) 2.5))
(newline)
(display (twice (ann 7 I64)))
(newline)

;; An output of an earlier prerequisite becomes a later prerequisite's input.
(struct (Box A)
  ((value A)))
(typeclass (Extract T)
  (type Output)
  (: extract (-> T Output)))
(instance (Extract (Box A))
  (type Output A)
  (define (extract value) (match value ((Box value) value))))
(instance (Add (! e) (Box A) B)
  (requires (Extract (Box A)) (Add e (Extract.Output (Box A)) B))
  (type Output (Add.Output e (Extract.Output (Box A)) B))
  (define (add a b) (add (extract a) b)))

(display (sum (Box (ann 4 I64)) 0.5))
(newline)

;; Recursion that makes its input smaller is permitted.
(typeclass (Flatten A)
  (type Output)
  (: flatten (-> A Output)))
(instance (Flatten I64)
  (type Output I64)
  (define (flatten value) value))
(instance (Flatten (Box A))
  (requires (Flatten A))
  (type Output (Flatten.Output A))
  (define (flatten value) (match value ((Box inner) (flatten inner)))))
(display (flatten (Box (Box (ann 9 I64)))))
(newline)

;; Class variables introduced by a macro retain their lexical marks.
(define-syntax define-identity-class
  (syntax-rules ()
    ((_ class method)
     (typeclass (class A)
       (type Output)
       (: method (-> A Output))))))
(define-identity-class Identity identity)
(instance (Identity I64)
  (type Output I64)
  (define (identity value) value))
(display (identity (ann 11 I64)))
(newline)
