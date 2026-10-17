(import
 (lofi core)
 (lofi base))

(def derive-reader
     (syntax-rules (data)
       ((_ (data Name (T ...)
             (constructor
              (reader Type accessor))))
        (def reader (All (T ...) (-> (Name T ...) Type))
             (lambda (value) (accessor value))))))
(def derive-probe
     (syntax-rules (data)
       ((_ (data Name (T ...)
             (constructor
              (reader Type accessor))))
        (reader (constructor 7)))))
(data Box (T)
  (box
   (read-value T box-value))
  (deriving derive-reader derive-probe))
(data Empty ()
  (empty)
  (deriving))
(read-value (box 42))
