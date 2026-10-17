(import
 (lofi base))
(def Only (typeclass ( T) (: only (-> T))))
(def lofi-migration-instance-1 (instance (Only I64) (only (lambda () (ann 42 I64)))))
(define-overload build (All (T) (=> ((Only T)) (-> I64 (Vector T))))
  (lambda (count) (make-vector count (only))))
(build (ann 1 I64))
