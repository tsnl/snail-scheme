(import
 (snail-core base)
 (snail-core io))

;; A recursive local function returned as a value.
(: make-counter (-> (-> I64 I64)))
(define (make-counter)
  (define (count n) (if (= n 0) 0 (+ 1 (count (- n 1)))))
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

(: evaluate (-> Expr I64))
(define (evaluate expr)
  (match expr
    ((Number value) value)
    ((Block statements)
     (fold-left (lambda (total statement) (+ total (run statement)))
                0
                statements))))

(: run (-> Statement I64))
(define (run statement)
  (match statement
    ((Evaluate expr) (evaluate expr))))

;; A struct whose field is an effectful function, with the row as a parameter.
(struct (Task e)
  ((step (-> I64 I64 ! e))))

(effect Note
  ((note (-> String Unit))))

(display ((make-counter) 25))
(newline)
(display (map Some (list 1 2)))
(newline)
(display (length (map (lambda (c) (match c ((Red) "r") ((Green) "g")))
                      (list (Red) (Green) (Red)))))
(newline)
(display (map Point-x
              (map (lambda (p) (Point-x-set p 9))
                   (list (Point 1 2) (Point 3 4)))))
(newline)
(display (vector-fold * 1 (list->vector (list 1 2 3 4 5))))
(newline)
(display (evaluate (Block (list (Evaluate (Number 4))
                                (Evaluate
                                 (Block (list (Evaluate (Number 6)))))))))
(newline)
(handle Note
    ((note (lambda (text) (write-line (string-append "note: " text)))))
  (for-each note (list "one" "two"))
  (display ((Task-step (Task (lambda (n) (note "stepping") (* n 2)))) 21))
  (newline))
(display (ann (None) (Option I64)))
(newline)
