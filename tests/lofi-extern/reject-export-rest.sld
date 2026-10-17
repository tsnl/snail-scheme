(import
 (lofi base))

(def worker (-> (Rest I32) I32)
     (lambda xs (car xs)))
(ann 42 I64)
