(import
 (lofi base))
(def calls
     (ref (ann 0 I64)))

(def observed (-> I64)
     (lambda () (ref-get calls)))
(def Box (datatype ()
           (box
            (value I64 unbox))))

(def invoke (-> I64)
     (lambda ()
       (begin
         (def first
              (alias (begin (ref-set! calls (ann 1 I64)) (ann 42 I64))))
         (def alias
              box)
         (unbox first))))
(ann 42 I64)
