;; Lofi rejects detached signatures as syntax. The original binding context is retained.
(import (lofi base))
(def identity (All (A) (-> A A))
     (lambda (value) value))
(def use
     (lambda ()
       (begin
         (: identity (-> I64 I64))
         (identity #t))))
(use)
