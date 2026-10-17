(import
 (lofi base))

(def effects
     (ref (ann 0 I64)))

(def checked (-> I64)
     (lambda ()
       (begin
         (def read-later
              (lambda ()
                (begin
                  (ref-set! effects (+ (ref-get effects) (ann 1 I64)))
                  later)))
         (def invoke
              read-later)
         (def early
              (invoke))
         (def later
              (ann 42 I64))
         early)))

(def observed (-> I64)
     (lambda () (ref-get effects)))
(ann 42 I64)
