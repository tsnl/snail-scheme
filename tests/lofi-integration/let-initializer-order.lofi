(import (lofi base))
(def cell
     (ref (ann 0 I64)))
(def record
     (lambda (digit)
       (begin
         (ref-set! cell (+ (* (ref-get cell) (ann 10 I64)) digit))
         digit)))
(begin (let lofi-migration-let-1 (record (ann 4 I64))) (let lofi-migration-let-2 (record (ann 2 I64)))
       (let first lofi-migration-let-1)
       (let second lofi-migration-let-2)
       (ref-get cell))
