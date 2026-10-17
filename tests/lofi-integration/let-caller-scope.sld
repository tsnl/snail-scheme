(import
 (lofi base))
(begin (let x (ann 42 I64))
       (begin (let lofi-migration-let-1 #t) (let lofi-migration-let-2 x) (let x lofi-migration-let-1)
              (let y lofi-migration-let-2)
              y))
