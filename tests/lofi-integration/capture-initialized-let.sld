(import (lofi base))

(def make-probe
     (lambda (start)
       (begin (let lofi-migration-let-1 (+ start (ann 1 I64)))
              (let lofi-migration-let-2 (vector start (+ start (ann 2 I64))))
              (let lofi-migration-let-3 (ref start))
              (let value lofi-migration-let-1)
              (let items lofi-migration-let-2)
              (let shared lofi-migration-let-3)
              (begin
                (def advance
                     (lambda (delta)
                       (begin
                         (ref-set! shared (+ (ref-get shared) delta))
                         (+ value (+ (vector-ref items (ann 1 I64)) (ref-get shared))))))
                (lambda (delta) (advance delta))))))

(def first
     (make-probe (ann 10 I64)))
(def second
     (make-probe (ann 20 I64)))
(+ (first (ann 1 I64)) (+ (first (ann 2 I64)) (second (ann 3 I64))))
