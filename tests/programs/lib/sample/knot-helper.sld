;; What the producer of (sample knot) imports, which imports (sample knot)
;; in turn.
(define-library (sample knot-helper)
  (export
   helper)
  (import
   (snail-core base)
   (sample knot))
  (begin

    (: helper I64)
    (define helper (+ knot 1))

    ))
