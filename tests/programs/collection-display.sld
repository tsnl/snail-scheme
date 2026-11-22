(import
 (snail core base)
 (snail core io))

;; Presentation is a deliberate choice; Repr remains available independently.
(instance (Show (Option String))
  (define (show (value (Option String))) (→ String)

    (match value
      ((Some text) text)
      ((None) "no input"))))

(instance (Show (List String))
  (define (show (items (List String))) (→ String)
    (string-join items ", ")))

(define (main (out OutputPort)) (→ Unit)
  (display out (Some "my string input"))
  (newline out)
  (display out (ann (None) (Option String)))
  (newline out)
  (display out (list "one" "two"))
  (newline out)
  (write out (Some "my string input"))
  (newline out)
  (write out (list "one" "two"))
  (newline out)
  (unit))
