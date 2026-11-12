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
(define answer (→ I64) 42)

;; A function's type is an arrow from its arguments to its result.
(define (square (n I64)) (→ I64)
  (* n n))

;; ---- Control ----

;; `if` always has both branches. `cond`, `case`, `when` and `unless` are
;; Scheme's.
(define (sign (n I64)) (→ String)
  (cond ((< n 0) "negative")
        ((= n 0) "zero")
        (else "positive")))

;; A named `let` is a loop. A call in tail position never grows the stack.
(define (sum-to (n I64)) (→ I64)
  (let loop ((i 1)
             (total 0))
    (if (> i n) total (loop (+ i 1) (+ total i)))))

;; ---- Lists and functions ----

;; A list holds values of one type and never changes. Functions are values,
;; and `lambda` makes one.
(define numbers (→ (List I64)) (list 1 2 3 4 5))

;; ---- Data ----

;; A struct has named fields; an enum has cases, each with its own fields.
;; A type's name builds it, and `(● point x)` reads a stored field.
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
(define (area (shape Shape)) (→ I64)
  (match shape
    ((Circle _ radius) (* 3 (square radius)))
    ((Rectangle _ width height) (* width height))))

;; There is no null and no exception: absence is an Option, and failure a
;; Result, both ordinary enums.
(define (divide (n I64) (d I64)) (→ (Result I64 String))
  (if (= d 0) (Err "division by zero") (Ok (quotient n d))))

;; ---- Generics and typeclasses ----

;; A typeclass names operations, and an instance gives them for one type.
(typeclass (Describe T)
  (: describe (Fn T → String)))

(instance (Describe Point)
  (define describe
    (lambda (point)
      (string-append "(" (i64->string (● point x)) ", " (i64->string (● point y)) ")"))))

(instance (Describe Bool)
  (define describe
    (lambda (b) (if b "yes" "no"))))

;; `All` makes a definition generic, and `requires` asks for instances.
;; Each use is compiled for its own types, so generic code costs what a
;; hand-written copy would.
(define (describe-all (items (List T))) (→ String) (∀ T) (⊨ (Describe T))
  (string-join (map describe items) " "))

;; ---- Mutation ----

;; A struct is a value. One a program changes lives in a cell, `Ref`, and
;; `set!` writes a place: the cell's content, or a field of it. Reading or
;; writing a cell performs `mut`, which the type records after `!`, so a
;; type without `! mut` promises that the function changes nothing.
(struct Counter
  ((count I64)))

(define (bump! (counter (Ref Counter))) (→ Unit) (! mut)
  (set! (● (ref-get counter) count) (+ (● (ref-get counter) count) 1)))

;; ---- Effects ----

;; An effect declares operations, and a handler implements them for the
;; code it runs. A function's row, after `!`, lists what it may perform:
;; `greet` asks, and whoever calls it decides what asking means.
(effect Ask
  ((ask (Fn → String))))

(define (greet) (→ String) (! Ask)
  (string-append "hello, " (ask)))

;; A `ctl` operation need not return. Its implementation receives
;; `resume`, the rest of the handled code, and calls it at most once:
;; here it collects each value emitted and carries on.
(effect Emit
  ((ctl emit (Fn I64 → Unit))))

(define (count-down (n I64)) (→ Unit) (! Emit)
  (when (> n 0)
    (emit n)
    (count-down (- n 1))))

;; ---- Macros ----

;; Macros are Scheme's `syntax-rules`, and hygienic: `swap!`'s own
;; `temporary` cannot capture the caller's.
(define-syntax swap!
  (syntax-rules ()
    ((_ a b) (let ((temporary (ref-get a)))
               (ref-set! a (ref-get b))
               (ref-set! b temporary)))))

(define main
  (lambda ()
    (write-line (string-append "seven squared is " (i64->string (square 7))))
    ;; Nothing converts implicitly: an I64 becomes an F64 only when asked.
    (write-line (f64->string (/ (i64->f64 answer) 8.0)))
    (write-line (sign -3))
    (display (sum-to 100))
    (newline)
    (write (map square (filter (lambda (n) (= (remainder n 2) 1)) numbers)))
    (newline)
    (display (fold-left + 0 numbers))
    (newline)
    (write (map area (list (Circle (Point 0 0) 2) (Rectangle (Point 1 1) 3 4))))
    (newline)
    (for-each (lambda (d)
                (match (divide 10 d)
                  ((Ok quotient) (write-line (i64->string quotient)))
                  ((Err reason) (write-line reason))))
              (list 2 0))
    (write-line (describe-all (list (Point 1 2) (Point 3 4))))
    (write-line (describe-all (list #t #f)))
    (let ((clicks (ref (Counter 0))))
      (bump! clicks)
      (bump! clicks)
      (display (● (ref-get clicks) count))
      (newline))
    (write-line (handle Ask
                    ((ask (lambda () "world")))
                  (greet)))
    (write (handle Emit
               ((emit (lambda (value resume) (Cons value (resume (unit))))))
             (count-down 3)
             (Nil)))
    (newline)
    ;; ---- Ownership ----

    ;; `once` makes work that runs at most once, and the checker proves an
    ;; owned value is used exactly once: called, passed on or dropped.
    (let ((job (once (lambda () (write-line "ran once")))))
      (call-once job))
    (let ((left (ref "left"))
          (right (ref "right")))
      (swap! left right)
      (write-line (string-append (ref-get left) " " (ref-get right))))
    (unit)))
