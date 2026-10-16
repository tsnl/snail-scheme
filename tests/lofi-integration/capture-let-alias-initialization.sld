(import (lofi base))

(def effects
     (ref (ann 0 I64)))

(def checked (-> I64)
     (lambda ()
       (begin
         (def make-probe
              (lambda ()
                (begin (let copy later)
                       (begin
                         (ref-set! effects (ann 1 I64))
                         (lambda () (copy (ann 42 I64)))))))
         (def saved
              (make-probe))
         (def later
              (lambda (x) x))
         (saved))))

(def observed (-> I64)
     (lambda () (ref-get effects)))

(ann 42 I64)
