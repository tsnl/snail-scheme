(import
 (snail core base)
 (snail core io)
 (sample representation))

(record Output
  ((text String)))

(define (line (value T)) (→ Unit) (! output-port) (∀ (T)) (⊨ (Repr T))
  (write value)
  (newline))

(enum Action
  (Rock)
  (Paper)
  (Scissors)
  (deriving Repr))

(instance (Show (!) Action)
  (define (show (action Action)) (→ String)

    (match action
      ((Rock) "rock")
      ((Paper) "paper")
      ((Scissors) "scissors"))))

(enum (Tree T)
  (Leaf)
  (Node ((left (Tree T))
         (value T)
         (right (Tree T))))
  (deriving Repr))

(record Secret
  ((text String)))

(record (Batch T)
  ((items (Vector T)))
  (deriving Repr))

(instance (Repr Secret)
  (define (repr (secret Secret)) (→ String)
    "#<secret>"))

;; A representation is pure, and write uses the active output-port handler.
(define (represented) (→ String) (repr (Some "pure")))

(define (main) (→ Unit) (! mut output-port)

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
  (line (new Pair (first "key") (second (Some "value"))))
  (line (list->vector (list "a" "b\tc")))
  (line (list->vector (ann (Nil) (List String))))
  (line (Rock))
  (display (Rock))
  (newline)
  (line (Node (ann (Leaf) (Tree String)) "root" (Node (Leaf) "child" (Leaf))))
  (line (new Envelope (name "parcel") (contents (list "a" "b"))))
  (line (new Batch (items (list->vector (list "one" "two")))))
  (line (new Secret (text "private")))
  (write-line (represented))
  (let ((output (new Output (text ""))))
    (handle output-port
        ((write-string (lambda (text)
                         (set! (● output text) (string-append (● output text) text)))))
      (write (Some "captured")))
    (write-line (● output text)))
  (unit))
