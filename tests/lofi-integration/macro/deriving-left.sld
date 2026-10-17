(define-library (macro deriving-left)
  (export schema)
  (import
   (lofi core)
   (only (macro deriving) define-named))
  (begin
    (define-named Box box schema box-value)))
