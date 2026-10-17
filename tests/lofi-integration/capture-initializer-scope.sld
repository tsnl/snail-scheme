(import
 (lofi base))

(def effects
     (ref (ann 0 I64)))
(def x
     (ann 40 I64))
(def make-probe
     (lambda ()
       (begin (let lofi-migration-let-1 (begin (ref-set! effects (+ (ref-get effects) (ann 1 I64))) (ann 1 I64)))
              (let lofi-migration-let-2 (begin (ref-set! effects (+ (ref-get effects) (ann 10 I64)))
                                               (lambda () x)))
              (let x lofi-migration-let-1)
              (let outer lofi-migration-let-2)
              (lambda () (+ x (outer))))))

(def saved
     (make-probe))
(+ (saved) (ref-get effects))
