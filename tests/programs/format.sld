;; The shared formatter: calls, special forms, a named let, imports and
;; record fields on their own lines, strings
;; and characters that hold parentheses, and comments that keep their place.
;; The editor also uses the same indentation rules on a selected range.
(import
 (snail core base)
 (snail core io)
 (snail shell format))

(define (source) (→ String)
  "(define (f x)\n(let loop ((i 0) (acc (Nil)))\n(if (< i x)\n(loop (+ i 1)\n(Cons i acc))\nacc)))\n(import (snail core base) (snail core io)\n(only (snail core table) empty-table))\n(record Point ((x F64) (y F64)) (deriving Show))\n(match value\n((Some x) (display x))\n(_ (unit)))\n(with-prompt stopping\n(lambda ()\n(display \"a\nb\")\n(display #\\())\n(lambda (value resume) (unit)))\n(foo bar\nbaz\nqux)\n(foo\nbar\nbaz)\n;;; three semicolons stay\n   ;;; even indented\n(let* ((a 1)\n(b 2))\n(+ a b))\n")

;; Binding bodies dedent both on format and when the editor indents one line.
(define (result-bindings) (→ String) "(result-let* ((a (Ok 1)))\n(Ok a))\n")

(define (main (out OutputPort)) (→ Unit)
  ((● out write-string) (format-source (source) format-width))
  ;; Reindenting only the second line leaves the third as it was.
  ((● out write-string) (indent-lines "(foo bar\nbaz\n  qux)\n" 1 1))
  ((● out write-string) (format-source (result-bindings) format-width))
  ((● out write-string) (indent-lines (result-bindings) 1 1))
  ;; The editor's line indentation uses the naming convention too, without
  ;; knowing these macros. Names that only contain `let` remain ordinary calls.
  (for-each (lambda (name)
              ((● out write-string) (indent-lines (string-append "(" name " ((x 1))\n(x))\n") 1 1)))
            (list "let" "let*" "retry-let" "custom-let*" "def-let" "outlet" "custom-let-later"))
  ((● out write-string) (indent-lines "(retry-let loop ((x 1))\n(loop x))\n" 1 1))
  (unit))
