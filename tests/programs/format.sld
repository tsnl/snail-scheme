;; Formatting as the repository's Emacs formatter does: calls, special
;; forms, a named let, imports and struct fields on their own lines, strings
;; and characters that hold parentheses, and comments that keep their place.
;; The expected output is what scripts/format-scheme makes of the same text.
(import
 (snail-core base)
 (snail-core io)
 (snail-core format))

(define source
  "(define (f x)\n(let loop ((i 0) (acc (Nil)))\n(if (< i x)\n(loop (+ i 1)\n(Cons i acc))\nacc)))\n(import (snail-core base) (snail-core io)\n(only (snail-core table) empty-table))\n(struct Point ((x F64) (y F64)) (deriving Show))\n(match value\n((Some x) (display x))\n(_ (unit)))\n(handle console\n((console-write (lambda (c) (unit))))\n(display \"a\nb\")\n(display #\\())\n(foo bar\nbaz\nqux)\n(foo\nbar\nbaz)\n;;; three semicolons stay\n   ;;; even indented\n(let* ((a 1)\n(b 2))\n(+ a b))\n")

(write-string (format-source source))

;; Reindenting only the second line leaves the third as it was.
(write-string (indent-lines "(foo bar\nbaz\n  qux)\n" 1 1))

;; Each character's class, for coloring: a definition's name, a comment, a
;; number, a type and a string.
(write-line (highlight-classes "(define (twice x) ; doubles\n  (* 2 x))"))
(write-line (highlight-classes "(: label (-> I64 String)) \"#\\\\(\""))

;; Both APIs use the same token boundaries, including incomplete editor input.
(: check-classes (-> String String Unit))
(define (check-classes source expected)
  (unless (string=? (highlight-classes source) expected)
    (panic (string-append "wrong highlighting: " source))))

(check-classes ",@" "qq")
(check-classes "#;x" "qq.")
(check-classes "#(1)" "qpnp")
(check-classes "#\\(" "hhh")
(check-classes "[1 ,@x]" "pn.qq.p")
(check-classes "\"a\\\n\"x" "sssss.")
(check-classes "\"a\n\nb\"" "ssssss")
(check-classes "#|a\n#|b|#\n|#x" "cccccccccccc.")
(check-classes ";a\nx" "cc..")
(check-classes "#|x|#\nx" "ccccc..")
(check-classes "\"x\"\nx" "sss..")
(check-classes "\"unterminated" "sssssssssssss")
(check-classes "#|\n\n" "cccc")
