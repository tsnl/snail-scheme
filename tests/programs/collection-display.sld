(import
 (snail core base)
 (snail core io))

;; Presentation is a deliberate choice; Repr remains available independently.
(instance (Show (!) (Option String))
  (define (show (value (Option String))) (→ String)

    (match value
      ((Some text) text)
      ((None) "no input"))))

(instance (Show (!) (List String))
  (define (show (items (List String))) (→ String)
    (string-join items ", ")))

(define (main) (→ Unit) (! output-port)
  (display (Some "my string input"))
  (newline)
  (display (ann (None) (Option String)))
  (newline)
  (display (list "one" "two"))
  (newline)
  (write (Some "my string input"))
  (newline)
  (write (list "one" "two"))
  (newline)
  (unit))
