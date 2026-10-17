(import (lofi base))
(def count
     (ref (ann 0 I64)))
(def Combine (typeclass ( T) (: combine (-> T T T))))
(def lofi-migration-instance-1 (instance (Combine I64) (combine member)))
(def make-member
     (lambda ()
       (begin
         (ref-set! count (+ (ref-get count) (ann 1 I64)))
         (lambda (a b) (+ a b)))))
(def member
     (make-member))
(combine (ann 1 I64) (ann 2 I64))
(+ (combine (ann 20 I64) (ann 21 I64)) (ref-get count))
