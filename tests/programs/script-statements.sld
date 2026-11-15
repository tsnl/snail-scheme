;; A script: its statements run in order as its entry, whose effects are
;; inferred, and each statement's value is dropped. A definition may come
;; after a statement that uses it.
(import
 (snail core base)
 (snail core io))

(write-line (greeting))

(define (greeting) (→ String) "hello from a script")

(+ 1 2)
(write-line "statements run in order")
