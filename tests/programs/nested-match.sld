(import
 (snail core base)
 (snail core io))

(define (describe (value (Option (Option I64)))) (→ String)
  (match value
    ((None) "none")
    ((Some (None)) "some none")
    ((Some (Some 0)) "zero")
    ((Some (Some n)) (show n))))

(define (classify (items (List I64))) (→ String)
  (match items
    ((Nil) "empty")
    ((Cons x (Nil)) (string-append "one " (show x)))
    ((Cons 1 (Cons _ _)) "starts with one")
    ((Cons _ (Cons y _)) (string-append "second " (show y)))))

(define (char-kind (c Char)) (→ String)
  (match c
    (#\a "a")
    (#\b "b")
    (_ "other")))

(define (bool-name (b Bool)) (→ String)
  (match b
    (#t "yes")
    (#f "no")))

(for-each write-line
          (list (describe (None))
                (describe (Some (None)))
                (describe (Some (Some 0)))
                (describe (Some (Some 7)))))
(for-each write-line
          (list (classify (list))
                (classify (list 5))
                (classify (list 1 2))
                (classify (list 4 5 6))))
(for-each write-line (list (char-kind #\a) (char-kind #\z) (bool-name #t) (bool-name #f)))
(match "hello"
  ("hi" (write-line "no"))
  ("hello" (write-line "string literal"))
  (_ (write-line "no")))
