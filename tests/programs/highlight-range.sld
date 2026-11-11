;; Compiler points stay points; display ranges follow the reader's lexical
;; boundaries, even for incomplete source. All offsets count scalars.
(import
 (snail core base)
 (snail core io)
 (snail shell highlight))

(define (check-range (text String) (point I64) (start I64) (marked String)) (→ Unit)
  (let ((range (highlight-range text point)))
    (unless (and (= (::first range) start)
                 (= (::second range) (+ start (string-length marked)))
                 (string=? (substring text (::first range) (::second range)) marked))
      (panic (string-append "unexpected display range at " (show point) " in " text)))))

;; Whole tokens, including a point inside an astral character or a string.
(check-range "alpha beta" 2 0 "alpha")
(check-range "α😀name rest" 1 0 "α😀name")
(check-range "x \"a\n(b)\" after" 6 2 "\"a\n(b)\"")
(check-range "#\\) next" 2 0 "#\\)")

;; A form crosses lines and nesting, stopping before the next datum.
(check-range "(alpha\n  (beta 123)) tail" 0 0 "(alpha\n  (beta 123))")
(check-range "(alpha\n  (beta 123)) tail" 9 9 "(beta 123)")
(check-range "(f \"( ] \\\" )\" #\\) #\\( ; [)\n #| ] #| ) |# ( |# #;(gone [x]) [kept]) after"
             0 0
             "(f \"( ] \\\" )\" #\\) #\\( ; [)\n #| ] #| ) |# ( |# #;(gone [x]) [kept])")
(check-range "' #; (ignored) '(a [b]) next" 0 0 "' #; (ignored) '(a [b])")
(check-range "#u8(0 255) next" 2 0 "#u8(0 255)")
(check-range "#;(skip (me)) kept" 8 0 "#;(skip (me))")
(check-range "; (ignored)\nnext" 3 0 "; (ignored)")
(check-range "#| ( #| ] |# ) |# kept" 4 0 "#| ( #| ] |# ) |#")

;; No enclosing-form guess for closing delimiters or whitespace. EOF
;; remains an empty range; the editor supplies its visible cell.
(check-range "(x) next" 2 2 ")")
(check-range "x\nnext" 1 1 "\n")
(check-range "x  next" 2 2 " ")
(check-range "x\tnext" 1 1 "\t")
(check-range "" 0 0 "")
(check-range "x" 1 1 "")
(check-range "x" 99 1 "")
(check-range "name" -1 0 "name")

;; Malformed source still terminates at a bounded lexical end.
(check-range "(a\n (b" 0 0 "(a\n (b")
(check-range "([x) y] rest" 0 0 "([x) y]")
(check-range "\"unterminated\n(x)" 5 0 "\"unterminated\n(x)")
(check-range "'" 0 0 "'")
(check-range "' #| comment |#" 0 0 "' #| comment |#")
(check-range "' ) next" 0 0 "' ")
(check-range "(#; ) next" 0 0 "(#; )")
(write-line "lexical display ranges passed")
