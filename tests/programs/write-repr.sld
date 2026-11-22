(import
 (snail core base)
 (snail core io)
 (sample representation))

(record Output
  ((text String)))

(define (line (out OutputPort) (value T)) (→ Unit) (! mut) (∀ (T)) (⊨ (Repr T))
  (write out value)
  (newline out))

(enum Action
  (Rock)
  (Paper)
  (Scissors)
  (deriving Repr))

(instance (Show Action)
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
  ((items (Array T)))
  (deriving Repr))

(instance (Repr Secret)
  (define (repr (secret Secret)) (→ String)
    "#<secret>"))

;; A representation is pure, and write uses the active output-port handler.
(define (represented) (→ String) (repr (Some "pure")))

(define (main (out OutputPort)) (→ Unit) (! mut)

  (line out "")
  (line out "quote: \"; slash: \\; line:\nreturn:\rtab:\tλ😀")
  (line out #\space)
  (line out #\newline)
  (line out #\tab)
  (line out #\λ)
  (line out (unit))
  (line out (list #t #f))
  (line out -9223372036854775808)
  (line out (ann -42 I32))
  (line out (ann 255 U8))
  (line out 1.5)
  (line out (ann 2.5 F32))
  (line out (ann (Nil) (List String)))
  (line out (ann (None) (Option String)))
  (line out (Some "a\nb"))
  (line out (list (Some "hello") (None)))
  (line out (ann (Ok "success") (Result String I64)))
  (line out (ann (Err "failure") (Result I64 String)))
  (line out (new Pair (first "key") (second (Some "value"))))
  (line out (list->array (list "a" "b\tc")))
  (line out (list->array (ann (Nil) (List String))))
  (line out (Rock))
  (display out (Rock))
  (newline out)
  (line out (Node (ann (Leaf) (Tree String)) "root" (Node (Leaf) "child" (Leaf))))
  (line out (new Envelope (name "parcel") (contents (list "a" "b"))))
  (line out (new Batch (items (list->array (list "one" "two")))))
  (line out (new Secret (text "private")))
  (write-line out (represented))
  (let ((output (new Output (text ""))))
    (write (new OutputPort
             (write-string (lambda (text)
                             (set! (● output text) (string-append (● output text) text)))))
           (Some "captured"))
    (write-line out (● output text)))
  (unit))
