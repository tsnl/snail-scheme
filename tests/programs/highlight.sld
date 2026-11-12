;; Highlighting by the reader's own lexical rules. Each sample is printed
;; with its tokens, as `class:"text"`, after a check that they tile it: each
;; starts where the one before ended, none is empty, and together they are
;; the sample. Where the reader accepts a sample, what it reads follows,
;; which the classes agree with: the reader skips comments and whitespace,
;; and reads a name, string or character where they are.
(import
 (snail core base)
 (snail core io)
 (snail shell highlight)
 (only (snail shell compiler read)
       read-text
       syntax->string
       compiling
       Failed
       Requested
       diagnostics->string))

;; ---- Printing ----

(define (quoted (text String)) (→ String)
  (string-append "\""
                 (string-concatenate (map (lambda (c)
                                            (cond ((char=? c #\") "\\\"")
                                                  ((char=? c #\\) "\\\\")
                                                  ((char=? c #\newline) "\\n")
                                                  (else (list->string (list c)))))
                                          (string->list text)))
                 "\""))

(define (token-text (chars (Vector Char)) (token Token)) (→ String)
  (vector->string (subvector chars (● token start) (● token end))))

(define (tiles? (tokens (List Token)) (index I64) (end I64)) (→ Bool)
  (match tokens
    ((Cons token rest)
     (and (= (● token start) index)
          (< index (● token end))
          (tiles? rest (● token end) end)))
    ((Nil) (= index end))))

(define (show-tokens (text String)) (→ Unit) (! output-port)
  (let* ((chars (string->vector text)) (tokens (highlight-tokens text)))
    (unless (and (tiles? tokens 0 (vector-length chars))
                 (string=?
                  (string-concatenate (map (lambda (token) (token-text chars token)) tokens))
                  text))
      (panic (string-append "the tokens do not tile " (quoted text))))
    (write-line (quoted text))
    (write-line (string-append "  "
                               (string-join (map (lambda (token)
                                                   (string-append (class-name (● token class))
                                                                  ":"
                                                                  (quoted
                                                                   (token-text chars token))))
                                                 tokens)
                                            " ")))))

(define (show-reading (text String)) (→ Unit) (! output-port)
  (show-tokens text)
  (write-line (string-append "  read: " (reading text))))

;; The forms the reader makes of `text`, or the error it stops with.
(define (reading (text String)) (→ String)
  (match (compiling (lambda () (read-text text "sample.sld")))
    ((Ok forms) (string-join (map syntax->string forms) " "))
    ((Err (Failed diagnostics)) (diagnostics->string diagnostics))
    ((Err (Requested _)) "the reader asked for an input")))

(define (main) (→ Unit) (! output-port)
  ;; ---- Samples ----

  ;; A definition's name, a comment, a number and the core forms.
  (show-reading "(define (twice (x I64)) (→ I64) ; doubles\n  (* 2 x))")
  (show-reading "(define label (→ String) \"label\")")
  (show-reading "(define ((adder n) x) (+ n x))")
  (show-reading "(struct Point ((x F64)) (deriving Show)) (match p ((Point x) x) (_ 0))")
  (show-reading
   "(effect ask (ctl ask (dyn (Fn Unit → I64)))) (handle ask ((ask (lambda (resume) 1))) body)")
  ;; Block comments nest.
  (show-reading "#| outer #| inner |# still outer |#x")
  ;; Escapes stay inside their string; `#\` takes the character after it,
  ;; whatever it is.
  (show-reading "\"line\\n quote\\\" slash\\\\ \\x41;\" #\\( #\\space #\\x41 #\\)")
  ;; Byte vectors, quotes, booleans and numbers; `+x` is a name.
  (show-reading "#u8(0 255) 'x '(a b) #t #false 1.5e3 -7 +x")
  ;; `#;` comments out the datum after it, and two of them two data. A
  ;; commented list runs to its own closing bracket, past the comments, the
  ;; strings and the `#;` inside it.
  (show-reading "#;(skip me) kept #; #; a 'b c")
  (show-reading "(f #;(a ; note\n #;b \"(\" c) d)")
  ;; A delimiter ends a token wherever it is: the quote mark in `x'y`, the
  ;; string after `"s"`, and the comment after `a`.
  (show-reading "(x'y \"s\"t #\\) a;b\n[c])")
  ;; What the reader rejects still classifies.
  (show-tokens ". #foo (a) ]")
  (show-tokens "\"unterminated\n(still a string")
  (show-tokens "#| unterminated")
  (show-tokens "(#; )")
  (unit))
