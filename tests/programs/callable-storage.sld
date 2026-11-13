(import
 (snail core base)
 (snail core io))

(define handlers (→ (List (Fn I64 → I64)))
  (list (lambda (value) (+ value 1))
        (lambda (value) (* value 2))))

(define code (→ (fn I64 → I64))
  (lambda (value) (+ value 10)))

(define (consume (function (FnOnce I64 → I64)))
  (→ I64)
  (function 7))

(define main
  (lambda ()
    (write-line (repr (map (lambda (function) (function 5)) handlers)))
    ;; A first-class constructor preserves argument count, too.
    (let ((to-once once))
      (let ((function (to-once (lambda (left right) (string-append left right)))))
        (write-line (function "first " "class"))))
    (let ((function (once (lambda (value) (code value)))))
      (write-line (show (function 5))))
    (write-line (show (consume (once (lambda (value) (code value))))))
    ;; A list transfers each one-shot procedure to exactly one caller.
    (let ((jobs (ann (list (once (lambda (value) (+ value 2)))
                           (once (lambda (value) (* value 3))))
                     (List (FnOnce I64 → I64)))))
      (match jobs
        ((Cons first (Cons second (Nil)))
         (write-line (show (first 10)))
         (write-line (show (second 10))))
        (other (drop other) (panic "expected two jobs"))))
    (unit)))
