;; The shared formatter: calls, special forms, a named let, imports and
;; struct fields on their own lines, strings
;; and characters that hold parentheses, and comments that keep their place.
;; Then lines past a width, here 40 columns: binding forms, calls, match arms,
;; a comment after the code,
;; a string that cannot break, effects after `!`, tokens written together,
;; and forms that share a line. CLI contracts live in tests/format-scheme.mjs.
(import
 (snail core base)
 (snail core io)
 (snail shell format))

(define source
  "(define (f x)\n(let loop ((i 0) (acc (Nil)))\n(if (< i x)\n(loop (+ i 1)\n(Cons i acc))\nacc)))\n(import (snail core base) (snail core io)\n(only (snail core table) empty-table))\n(struct Point ((x F64) (y F64)) (deriving Show))\n(match value\n((Some x) (display x))\n(_ (unit)))\n(handle console\n((console-write (lambda (c) (unit))))\n(display \"a\nb\")\n(display #\\())\n(foo bar\nbaz\nqux)\n(foo\nbar\nbaz)\n;;; three semicolons stay\n   ;;; even indented\n(let* ((a 1)\n(b 2))\n(+ a b))\n")

(write-string (format-source source format-width))

(define long
  (string-append
   "(define (f x) (let* ((a (foo x)) (b (bar a)) (c (baz b))) (+ a b c)))\n"
   "(define (make-thing alpha beta gamma delta) (list alpha beta))\n"
   "(result-let* ((a (foo x)) (b (bar a)) (c (baz b))) (+ a b c) (Ok c))\n"
   "(string-append \"first part\" (symbol->string name) \"last part\")\n"
   "(error \"a message that is long enough to matter\")\n"
   "(match option ((Some value) (display (string-append \"found \" value))) ((None) (display \"nothing\")))\n"
   "(foo alpha beta gamma delta epsilon) ; fits: the comment does not count\n"
   "(foo alpha beta gamma delta epsilon zeta) ; stays on the last line\n"
   "(define message \"a string much longer than forty columns cannot break\")\n"
   "(: run (-> Config (List String) Status ! fs console))\n"
   "(bytes #u8(1 2 3 4 5 6 7 8 9 10 11 12 13 14))\n"
   "(display \"one\") (display \"two\") (display \"three\")\n"))

(define broken (format-source long 40))
(write-string broken)

;; Formatting what formatting made changes nothing.
(write-line (if (string=? broken (format-source broken 40))
                "idempotent"
                "not idempotent"))

;; Reindenting only the second line leaves the third as it was.
(write-string (indent-lines "(foo bar\nbaz\n  qux)\n" 1 1))

;; Binding bodies dedent both on format and when the editor indents one line.
(define result-bindings "(result-let* ((a (Ok 1)))\n(Ok a))\n")
(write-string (format-source result-bindings format-width))
(write-string (indent-lines result-bindings 1 1))

;; The editor's line indentation uses the naming convention too, without
;; knowing these macros. Names that only contain `let` remain ordinary calls.
(for-each (lambda (name)
            (write-string (indent-lines (string-append "(" name " ((x 1))\n(x))\n") 1 1)))
          (list "let" "let*" "retry-let" "custom-let*" "def-let" "outlet" "custom-let-later"))
(write-string (indent-lines "(retry-let loop ((x 1))\n(loop x))\n" 1 1))
