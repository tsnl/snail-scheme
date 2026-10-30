;; Snail-Core in ten minutes. Every line of this file runs:
;;
;;   ./scripts/snail-tool run examples/tour.sld
;;
;; prints what `examples/tour.out` holds, and the test suite checks it.
(import
 (snail core base)
 (snail core io))

;; ---- Values and definitions ----

;; A top-level `define` names a value, and `:` declares its type. The
;; scalars are I32, I64, F32, F64, Bool, Char, String and Unit; an integer
;; literal is an I64 unless something says otherwise.
(: answer I64)
(define answer 42)

;; A function's type is an arrow from its arguments to its result.
(: square (-> I64 I64))
(define (square n)
  (* n n))

(write-line (string-append "seven squared is " (i64->string (square 7))))

;; Nothing converts implicitly: an I64 becomes an F64 only when asked.
(write-line (f64->string (/ (i64->f64 answer) 8.0)))

;; ---- Control ----

;; `if` always has both branches. `cond`, `case`, `when` and `unless` are
;; Scheme's.
(: sign (-> I64 String))
(define (sign n)
  (cond ((< n 0) "negative")
        ((= n 0) "zero")
        (else "positive")))

(write-line (sign -3))

;; A named `let` is a loop. A call in tail position never grows the stack.
(: sum-to (-> I64 I64))
(define (sum-to n)
  (let loop ((i 1)
             (total 0))
    (if (> i n) total (loop (+ i 1) (+ total i)))))

(display (sum-to 100))
(newline)

;; ---- Lists and functions ----

;; A list holds values of one type and never changes. Functions are values,
;; and `lambda` makes one.
(: numbers (List I64))
(define numbers (list 1 2 3 4 5))

(display (map square (filter (lambda (n) (= (remainder n 2) 1)) numbers)))
(newline)
(display (fold-left + 0 numbers))
(newline)

;; ---- Data ----

;; A struct has named fields; an enum has cases, each with its own fields.
;; A type's name builds it, and `Point-x` reads a field.
(struct Point
  ((x I64)
   (y I64)))

(enum Shape
  (Circle
   ((center Point)
    (radius I64)))
  (Rectangle
   ((corner Point)
    (width I64)
    (height I64))))

;; `match` takes data apart. A match that misses a case does not compile.
(: area (-> Shape I64))
(define (area shape)
  (match shape
    ((Circle _ radius) (* 3 (square radius)))
    ((Rectangle _ width height) (* width height))))

(display (map area (list (Circle (Point 0 0) 2) (Rectangle (Point 1 1) 3 4))))
(newline)

;; There is no null and no exception: absence is an Option, and failure a
;; Result, both ordinary enums.
(: divide (-> I64 I64 (Result I64 String)))
(define (divide n d)
  (if (= d 0) (Err "division by zero") (Ok (quotient n d))))

(for-each (lambda (d)
            (match (divide 10 d)
              ((Ok quotient) (write-line (i64->string quotient)))
              ((Err reason) (write-line reason))))
          (list 2 0))

;; ---- Generics and typeclasses ----

;; A typeclass names operations, and an instance gives them for one type.
(typeclass (Describe T)
  (: describe (-> T String)))

(instance (Describe Point)
  (define (describe point)
    (string-append "(" (i64->string (Point-x point)) ", " (i64->string (Point-y point)) ")")))

(instance (Describe Bool)
  (define (describe b)
    (if b "yes" "no")))

;; `All` makes a definition generic, and `requires` asks for instances.
;; Each use is compiled for its own types, so generic code costs what a
;; hand-written copy would.
(: describe-all (All (T) (requires (Describe T)) (-> (List T) String)))
(define (describe-all items)
  (string-join (map describe items) " "))

(write-line (describe-all (list (Point 1 2) (Point 3 4))))
(write-line (describe-all (list #t #f)))

;; ---- Mutation ----

;; A value changes only through a field declared `mut`. Reading or writing
;; one performs `mut`, which the type records after `!`, so a type without
;; `! mut` promises that the function changes nothing.
(struct Counter
  ((count mut I64)))

(: bump! (-> Counter Unit ! mut))
(define (bump! counter)
  (Counter-count-set! counter (+ (Counter-count counter) 1)))

(let ((clicks (Counter 0)))
  (bump! clicks)
  (bump! clicks)
  (display (Counter-count clicks))
  (newline))

;; ---- Effects ----

;; An effect declares operations, and a handler implements them for the
;; code it runs. A function's row, after `!`, lists what it may perform:
;; `greet` asks, and whoever calls it decides what asking means.
(effect Ask
  ((ask (-> String))))

(: greet (-> String ! Ask))
(define (greet)
  (string-append "hello, " (ask)))

(write-line (handle Ask
                ((ask (lambda () "world")))
              (greet)))

;; A `ctl` operation need not return. Its implementation receives
;; `resume`, the rest of the handled code, and calls it at most once:
;; here it collects each value emitted and carries on.
(effect Emit
  ((ctl emit (-> I64 Unit))))

(: count-down (-> I64 Unit ! Emit))
(define (count-down n)
  (when (> n 0)
    (emit n)
    (count-down (- n 1))))

(display (handle Emit
             ((emit (lambda (value resume) (Cons value (resume (unit))))))
           (count-down 3)
           (Nil)))
(newline)

;; ---- Ownership ----

;; `once` makes work that runs at most once, and the checker proves an
;; owned value is used exactly once: called, passed on or dropped.
(let ((job (once (lambda () (write-line "ran once")))))
  (call-once job))

;; ---- Macros ----

;; Macros are Scheme's `syntax-rules`, and hygienic: `swap!`'s own
;; `temporary` cannot capture the caller's.
(define-syntax swap!
  (syntax-rules ()
    ((_ a b) (let ((temporary (ref-get a)))
               (ref-set! a (ref-get b))
               (ref-set! b temporary)))))

(let ((left (ref "left"))
      (right (ref "right")))
  (swap! left right)
  (write-line (string-append (ref-get left) " " (ref-get right))))

;; From here: the chapters on types, effects and ownership say what each
;; form means, and the tutorials that follow are small programs that use
;; them.
