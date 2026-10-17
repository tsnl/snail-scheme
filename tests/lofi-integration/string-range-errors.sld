(import
 (lofi base))
(def target
     (string-copy "abc"))
(def source
     "XY")

(def negative-length (-> I64)
     (lambda () (string-length (make-string (ann -1 I64)))))

(def overflow-length (-> I64)
     (lambda () (string-length (make-string (ann 4294967295 I64)))))

(def huge-length (-> I64)
     (lambda () (string-length (make-string (ann 9223372036854775807 I64)))))

(def negative-index (-> Char)
     (lambda () (string-ref target (ann -1 I64))))

(def endpoint-index (-> Char)
     (lambda () (string-ref target (ann 3 I64))))

(def wrapped-index (-> Unit)
     (lambda () (string-set! target (ann 4294967295 I64) #\null)))

(def empty-index (-> Char)
     (lambda () (string-ref (string) (ann 0 I64))))

(def reversed-range (-> Unit)
     (lambda () (string-copy! target (ann 0 I64) source (ann 2 I64) (ann 1 I64))))

(def negative-range (-> Unit)
     (lambda () (string-copy! target (ann 0 I64) source (ann -1 I64) (ann 0 I64))))

(def long-source (-> Unit)
     (lambda () (string-copy! target (ann 0 I64) source (ann 0 I64) (ann 3 I64))))

(def short-target (-> Unit)
     (lambda () (string-copy! target (ann 2 I64) source (ann 0 I64) (ann 2 I64))))

(def empty-target-overflow (-> Unit)
     (lambda () (string-copy! target (ann 4294967295 I64) source (ann 0 I64) (ann 0 I64))))

(def empty-source-overflow (-> Unit)
     (lambda () (string-copy! target (ann 0 I64) source (ann 4294967295 I64) (ann 4294967295 I64))))

(def empty-source-bounds (-> Unit)
     (lambda () (string-copy! target (ann 0 I64) source (ann 3 I64) (ann 3 I64))))

(def empty-target-bounds (-> Unit)
     (lambda () (string-copy! target (ann 4 I64) source (ann 0 I64) (ann 0 I64))))

(def negative-substring (-> I64)
     (lambda () (string-length (substring source (ann -1 I64) (ann 0 I64)))))

(def reversed-substring (-> I64)
     (lambda () (string-length (substring source (ann 2 I64) (ann 1 I64)))))

(def long-substring (-> I64)
     (lambda () (string-length (substring source (ann 0 I64) (ann 3 I64)))))

(def unchanged (-> Bool)
     (lambda ()
       (begin (let before (string=? target "abc"))
              (begin
                (string-set! target (ann 0 I64) #\Z)
                (if before (string=? target "Zbc") #f)))))
(ann 42 I64)
