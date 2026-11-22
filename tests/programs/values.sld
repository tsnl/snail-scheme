(import
 (snail core base)
 (snail core io))

;; A recursive local function returned as a value.
(define (make-counter) (→ (Fn I64 → I64))
  (define count (lambda (n) (if (= n 0) 0 (+ 1 (count (- n 1))))))
  count)

(record Point
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

;; A record whose field is an effectful function, with the row as a parameter.
(record (Task e)
  ((step (Fn I64 → I64 ! e))))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (display out ((make-counter) 25))
  (newline out)
  (write out (map Some (list 1 2)))
  (newline out)
  (display out
           (length
            (map (lambda (c) (match c ((Red) "r") ((Green) "g"))) (list (Red) (Green) (Red)))))
  (newline out)
  (write out (map (lambda (record) (● record x))
                  (map (lambda (p) (Point-x-set p 9))
                       (list (new Point (x 1) (y 2)) (new Point (x 3) (y 4))))))
  (newline out)
  (display out (array-fold * 1 (list->array (list 1 2 3 4 5))))
  (newline out)
  (display out
           (evaluate
            (Block (list (Evaluate (Number 4)) (Evaluate (Block (list (Evaluate (Number 6)))))))))
  (newline out)
  (let ((note (lambda (text) (write-line out (string-append "note: " text)))))
    (for-each note (list "one" "two"))
    (display out ((● (new Task (step (lambda (n) (note "stepping") (* n 2)))) step) 21))
    (newline out))
  (write out (ann (None) (Option I64)))
  (newline out)
  (unit))
