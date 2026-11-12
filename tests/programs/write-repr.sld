(import
 (snail core base)
 (snail core io)
 (sample representation))

(define (line (value T)) (→ Unit) (! output-port) (∀ T) (⊨ (Repr T))
  (write value)
  (newline))

(enum Action
  (Rock)
  (Paper)
  (Scissors)
  (deriving Repr))

(instance (Show (!) Action)
  (define show (lambda (action)
                 (match action
                   ((Rock) "rock")
                   ((Paper) "paper")
                   ((Scissors) "scissors")))))

(enum (Tree T)
  (Leaf)
  (Node ((left (Tree T))
         (value T)
         (right (Tree T))))
  (deriving Repr))

(struct Secret
  ((text String)))

(struct (Batch T)
  ((items (Vector T)))
  (deriving Repr))

(instance (Repr Secret)
  (define repr (lambda (secret) "#<secret>")))

;; A representation is pure, and write uses the active output-port handler.
(define represented (→ String) (repr (Some "pure")))

(define main
  (lambda ()
    (line "")
    (line "quote: \"; slash: \\; line:\nreturn:\rtab:\tλ😀")
    (line #\space)
    (line #\newline)
    (line #\tab)
    (line #\λ)
    (line (unit))
    (line (list #t #f))
    (line -9223372036854775808)
    (line (ann -42 I32))
    (line (ann 255 U8))
    (line 1.5)
    (line (ann 2.5 F32))
    (line (ann (Nil) (List String)))
    (line (ann (None) (Option String)))
    (line (Some "a\nb"))
    (line (list (Some "hello") (None)))
    (line (ann (Ok "success") (Result String I64)))
    (line (ann (Err "failure") (Result I64 String)))
    (line (Pair "key" (Some "value")))
    (line (list->vector (list "a" "b\tc")))
    (line (list->vector (ann (Nil) (List String))))
    (line (Rock))
    (display (Rock))
    (newline)
    (line (Node (ann (Leaf) (Tree String)) "root" (Node (Leaf) "child" (Leaf))))
    (line (Envelope "parcel" (list "a" "b")))
    (line (Batch (list->vector (list "one" "two"))))
    (line (Secret "private"))
    (write-line represented)
    (let ((output (ref "")))
      (handle output-port
          ((write-string (lambda (text)
                           (ref-set! output (string-append (ref-get output) text)))))
        (write (Some "captured")))
      (write-line (ref-get output)))
    (unit)))
