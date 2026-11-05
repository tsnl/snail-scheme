#lang snail
;; A layout entry imports a layout library, which imports explicit sexp.
import (snail core base) (snail core io) (sample reader-layout)

let ((x 10)
     (y 20))
  write-line (show (twice (+ x y)))
  let ((z (+ x y)))
    write-line (show z)

define-syntax announce
  (syntax-rules ()
    ((_ label body ...) (begin (write-line label) body ...)))

announce "macro body"
  write-line "first"
  write-line "second"

if #t
  begin
    write-line "branch"
    write-line "result"
  write-line "unreached"

write-line (show (let loop ((n 3)) (if (= n 0) 0 (+ n (loop (- n 1))))))
write-line "done"
