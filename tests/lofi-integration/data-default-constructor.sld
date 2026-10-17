(import
 (lofi base))
(def Choice (datatype ()
              (empty)
              (full
               (value I64))))
(def lofi-migration-instance-1 (instance (Default Choice) (default empty)))
(def choices
     (ann (make-vector (ann 2 I64)) (Vector Choice)))
(match (vector-ref choices (ann 1 I64)) ((empty) (ann 9 I64)) ((full value) value))
