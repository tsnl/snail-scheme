(import (scheme base) (scheme write) (snail-scheme extensions))

(display (rust-triple 14))
(newline)
(rust-remember (cons "a Scheme pair retained by Rust" 42))
;; A Rust root remains live while Scheme creates further garbage.
(let loop ((n 100000))
  (if (> n 0) (begin (cons n n) (loop (- n 1)))))
(write (rust-recalled))
(newline)

(display (rust-call (lambda (n) (cons n (rust-triple n))) 14))
(newline)

(rust-root-stress (rust-recalled))
(rust-forget)

(define returned-closure (rust-call (lambda (n) (lambda () (rust-triple n))) 14))
(display (returned-closure))
(newline)
