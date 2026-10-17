(import (lofi base))
(def Point (datatype () (point (x I64 point-x) (y I64 point-y))))
(def lofi-migration-instance-1 (instance (Default Point) (default (lambda () (point (ann 4 I64) (ann 8 I64))))))
(def points
     (ann (make-vector (ann 3 I64)) (Vector Point)))
(point-y (vector-ref points (ann 2 I64)))
