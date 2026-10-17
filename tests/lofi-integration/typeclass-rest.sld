(import
 (lofi base))
(def Choose (typeclass ( T) (: choose (-> T (Rest T) T))))
(def lofi-migration-instance-1 (instance (Choose I64)
                                         (choose (lambda (first . remaining)
                                                   (if (null? remaining) first (car remaining))))))
(+ (choose (ann 0 I64) (ann 22 I64) (ann 99 I64)) (choose (ann 20 I64)))
