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

(define (token-text (chars (Array Char)) (token Token)) (→ String)
  (array->string (subarray chars (● token start) (● token end))))

(define (tiles? (tokens (List Token)) (index I64) (end I64)) (→ Bool)
  (match tokens
    ((Cons token rest)
     (and (= (● token start) index)
          (< index (● token end))
          (tiles? rest (● token end) end)))
    ((Nil) (= index end))))

(define (show-tokens (out OutputPort) (text String)) (→ Unit) (! mut)
  (let* ((chars (string->array text)) (tokens (highlight-tokens text)))
    (unless (and (tiles? tokens 0 (array-length chars))
                 (string=?
                  (string-concatenate (map (lambda (token) (token-text chars token)) tokens))
                  text))
      (panic (string-append "the tokens do not tile " (quoted text))))
    (write-line out (quoted text))
    (write-line out (string-append "  "
                                   (string-join (map (lambda (token)
                                                       (string-append (class-name (● token class))
                                                                      ":"
                                                                      (quoted
                                                                       (token-text chars token))))
                                                     tokens)
                                                " ")))))

(define (show-reading (out OutputPort) (text String)) (→ Unit) (! mut)
  (show-tokens out text)
  (write-line out (string-append "  read: " (reading text))))

;; The forms the reader makes of `text`, or the error it stops with.
(define (reading (text String)) (→ String)
  (match (compiling (lambda () (read-text text "sample.sld")))
    ((Ok forms) (string-join (map syntax->string forms) " "))
    ((Err (Failed diagnostics)) (diagnostics->string diagnostics))
    ((Err (Requested _)) "the reader asked for an input")))

(define (main (out OutputPort)) (→ Unit) (! mut)
  ;; ---- Samples ----

  ;; A definition's name, a comment, a number and the core forms.
  (show-reading out "(define (twice (x I64)) (→ I64) ; doubles\n  (* 2 x))")
  (show-reading out "(define label (→ String) \"label\")")
  (show-reading out "(define (adder (n I64)) (→ (Fn I64 → I64)) (lambda (x) (+ n x)))")
  (show-reading out "(record Point ((x F64)) (deriving Show)) (match p ((Point x) x) (_ 0))")
  (show-reading out
                "(define asking (make-prompt)) (with-prompt asking body (lambda (value resume) (resume 1)))")
  ;; Block comments nest.
  (show-reading out "#| outer #| inner |# still outer |#x")
  ;; Escapes stay inside their string; `#\` takes the character after it,
  ;; whatever it is.
  (show-reading out "\"line\\n quote\\\" slash\\\\ \\x41;\" #\\( #\\space #\\x41 #\\)")
  ;; Byte arrays, quotes, booleans and numbers; `+x` is a name.
  (show-reading out "#u8(0 255) 'x '(a b) #t #false 1.5e3 -7 +x")
  ;; `#;` comments out the datum after it, and two of them two data. A
  ;; commented list runs to its own closing bracket, past the comments, the
  ;; strings and the `#;` inside it.
  (show-reading out "#;(skip me) kept #; #; a 'b c")
  (show-reading out "(f #;(a ; note\n #;b \"(\" c) d)")
  ;; A delimiter ends a token wherever it is: the quote mark in `x'y`, the
  ;; string after `"s"`, and the comment after `a`.
  (show-reading out "(x'y \"s\"t #\\) a;b\n[c])")
  ;; What the reader rejects still classifies.
  (show-tokens out ". #foo (a) ]")
  (show-tokens out "\"unterminated\n(still a string")
  (show-tokens out "#| unterminated")
  (show-tokens out "(#; )")
  (unit))
