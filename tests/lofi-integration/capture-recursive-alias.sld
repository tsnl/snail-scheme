(import
 (lofi base))

(def effects
     (ref (ann 0 I64)))

(def checked (-> I64)
     (lambda ()
       (begin (let x (ann 42 I64))
              (begin
                (def read-alias
                     (lambda ()
                       (begin
                         (ref-set! effects (ann 1 I64))
                         alias)))
                (def early
                     (read-alias))
                (def alias
                     x)
                (read-alias)))))

(def observed (-> I64)
     (lambda () (ref-get effects)))

(ann 42 I64)
