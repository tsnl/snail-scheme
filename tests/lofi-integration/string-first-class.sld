(import
 (lofi base))
(def allocate
     (lambda (maker) (maker (ann 2 I64) #\λ)))
(def edit
     (lambda (writer target) (writer target (ann 1 I64) #\é)))
(def copy
     (lambda (copier target source) (copier target (ann 0 I64) source (ann 0 I64) (ann 2 I64))))
(def value
     (allocate (ann make-string (-> I64 Char String))))
(def result
     (make-string (ann 2 I64)))
(edit string-set! value)
(copy string-copy! result value)
(def lofi-migration-instance-1 (instance (Default String) (default (lambda () (string)))))
(def values
     (ann (make-vector (ann 2 I64)) (Vector String)))
(if (if (string=? result "λé")
        (not (string-eq? (vector-ref values (ann 0 I64)) (vector-ref values (ann 1 I64))))
        #f)
    (ann 42 I64)
    (unreachable))
