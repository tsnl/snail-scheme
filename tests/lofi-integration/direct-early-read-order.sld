(import
 (lofi base))

(def state
     (ref (ann 0 I64)))

(def checked (-> I64)
     (lambda ()
       (begin
         (def read-later
              (lambda ()
                (begin
                  (ref-set! state (ann 7 I64))
                  (vector-ref later (ann 0 I64)))))
         (def early
              (read-later))
         (def later
              (make-vector (ann 1 I64) (ann 42 I64)))
         early)))

(def observed (-> I64)
     (lambda () (ref-get state)))

(ann 42 I64)
