(define-library (snail-scheme source)
  (export
   <loc>
   loc?
   make-loc
   loc-filename
   loc-line
   loc-column)

  (import
   (scheme base))

  (begin

    ;; ---- Source locations ----

    (define-record-type <loc>
      (make-loc
       filename ; string
       line ; int, 1-indexed
       column) ; int, 1-indexed
      loc?
      (filename loc-filename)
      (line loc-line)
      (column loc-column))))
