(import
 (lofi base))
(def calls
     (ref (ann 0 I64)))
(def Box (datatype ( T)
           (box
            (value T unbox))))

(def make (All (T) (-> T (Box T)))
     (begin (ref-set! calls (+ (ref-get calls) (ann 1 I64))) box))
(unbox (make 42))
