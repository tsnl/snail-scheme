;; A library whose module a host loads by itself, from another program's
;; build, and calls through a Funcref.
(define-library (cell)
  (export
   run)
  (import
   (snail core base))
  (begin

    (: run (-> I64 I64))
    (define (run n)
      (+ n 1))))
