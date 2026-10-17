(import
 (lofi base))
(def identity
     (lambda (x) x))
(if (identity #t) (+ (identity (ann 40 I64)) (identity (ann 2 I64))) (ann 0 I64))
