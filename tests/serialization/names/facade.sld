(define-library (names facade)
  (export (rename Stock Renamed) (rename stock make-renamed) (rename stock-ore renamed-ore))
  (import
   (names left)))
