(import
 (snail core base)
 (snail core io))

;; A recursive local function returned as a value.
(define (make-counter) (→ (dyn (Fn I64 → I64)))
  (define count (lambda (n) (if (= n 0) 0 (+ 1 (count (- n 1))))))
  count)

(struct Point
  ((x I64)
   (y I64)))

(enum Color
  (Red)
  (Green))

;; Mutually recursive data.
(enum Expr
  (Number ((value I64)))
  (Block ((statements (List Statement)))))

(enum Statement
  (Evaluate ((expr Expr))))

(define (evaluate (expr Expr)) (→ I64)
  (match expr
    ((Number value) value)
    ((Block statements)
     (fold-left (lambda (total statement) (+ total (run statement))) 0 statements))))

(define (run (statement Statement)) (→ I64)
  (match statement
    ((Evaluate expr) (evaluate expr))))

;; A struct whose field is an effectful function, with the row as a parameter.
(struct (Task e)
  ((step (dyn (Fn I64 → I64 ! e)))))

(effect Note
  ((note (dyn (Fn String → Unit)))))

(display ((make-counter) 25))
(newline)
(write (map Some (list 1 2)))
(newline)
(display (length (map (lambda (c) (match c ((Red) "r") ((Green) "g"))) (list (Red) (Green) (Red)))))
(newline)
(write (map (lambda (record) (● record x))
            (map (lambda (p) (Point-x-set p 9)) (list (Point 1 2) (Point 3 4)))))
(newline)
(display (vector-fold * 1 (list->vector (list 1 2 3 4 5))))
(newline)
(display
 (evaluate (Block (list (Evaluate (Number 4)) (Evaluate (Block (list (Evaluate (Number 6)))))))))
(newline)
(handle Note
    ((note (lambda (text) (write-line (string-append "note: " text)))))
  (for-each note (list "one" "two"))
  (display ((● (Task (lambda (n) (note "stepping") (* n 2))) step) 21))
  (newline))
(write (ann (None) (Option I64)))
(newline)
