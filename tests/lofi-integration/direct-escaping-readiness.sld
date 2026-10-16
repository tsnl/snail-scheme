(import (lofi base))

(def state
     (ref (ann 0 I64)))
(def make-probe
     (lambda (early?)
       (begin
         (def probe
              (lambda ()
                (begin
                  (ref-set! state (+ (ann 1 I64) (ref-get state)))
                  (later))))
         (def early
              (if early? (probe) (ann 0 I64)))
         (def later
              (lambda () (vector-ref payload (ann 0 I64))))
         (def payload
              (make-vector (ann 1 I64) (ann 42 I64)))
         probe)))
(def saved
     (make-probe #f))

(def checked (-> I64)
     (lambda () ((make-probe #t))))

(def before (-> I64)
     (lambda () (ref-get state)))

(def after (-> I64)
     (lambda () (saved)))

(def observed (-> I64)
     (lambda () (ref-get state)))

(ann 42 I64)
