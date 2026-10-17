(define-library (macro declaration-facade)
  (export define-machine)
  (import
   (rename (only (macro declarations) define-counter)
           (define-counter define-machine))))
