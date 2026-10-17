(import
 (lofi base))
(def Empty (datatype ()
             (empty)))
(def calls
     (ref (ann 0 I64)))

(def observed (-> I64)
     (lambda () (ref-get calls)))

(def invoke (-> I64)
     (lambda ()
       (begin
         ;; Evaluating a nullary call's operator can have effects and fail readiness.
         (def first
              ((begin (ref-set! calls (ann 1 I64)) alias)))
         (def alias
              empty)
         (match first ((empty) (ann 42 I64))))))
(ann 42 I64)
