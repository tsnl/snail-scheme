(import
 (lofi base))
(def bad
     (lambda (captured)
       (begin (let get (lambda (ignored) captured))
              (+ (get (ann 0 I64)) (if (get #t) (ann 1 I64) (ann 2 I64))))))
(bad 41)
