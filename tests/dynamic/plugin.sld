;; A program built apart from the host, whose modules the host loads while
;; it runs.
(import
 (snail-core base)
 (snail-core io)
 (cell))

(display (run 0))
(newline)
