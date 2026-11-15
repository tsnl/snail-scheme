;; The colors Zed's highlights.scm gives each form; `tree-sitter test` checks
;; every mark under a line against that line.

(define (twice (f (Fn I64 → I64)) (x I64)) (→ I64) (f (f x)))
; <- punctuation.bracket
;^ keyword
;        ^ function
;                  ^ type
;                         ^ keyword

(define limit 10)
;       ^ function
;             ^ number

(type Label String)
;^ keyword
;     ^ type
;           ^ type

(match value ((Some x) #\a) (_ "text"))
;^ keyword
;              ^ type
;                      ^ string.special
;                              ^ string

#| a #| nested |# comment |# #t
;       ^ comment
;                            ^ boolean

#; (skipped) '(1 2)
;   ^ comment
;            ^ punctuation.special
;              ^ number
