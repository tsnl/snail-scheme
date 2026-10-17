(import
 (lofi base)
 (lofi bytes))
(def target
     (bytevector (ann 1 I64) (ann 2 I64) (ann 3 I64)))
(def effects
     (ref (ann 0 I64)))
(def mark
     (lambda (digit value)
       (begin
         (ref-set! effects (+ (* (ref-get effects) (ann 10 I64)) digit)) value)))

(def negative-length (-> I64)
     (lambda () (bytevector-length (make-bytevector (ann -1 I64)))))

(def overflow-length (-> I64)
     (lambda () (bytevector-length (make-bytevector (ann 4294967296 I64)))))

(def empty-invalid-fill (-> I64)
     (lambda () (bytevector-length (make-bytevector (ann 0 I64) (ann 256 I64)))))

(def negative-fill (-> I64)
     (lambda () (bytevector-length (make-bytevector (ann 0 I64) (ann -1 I64)))))

(def negative-index (-> I64)
     (lambda () (bytevector-u8-ref target (ann -1 I64))))

(def wrapped-index (-> I64)
     (lambda () (bytevector-u8-ref target (ann 4294967296 I64))))

(def endpoint-index (-> I64)
     (lambda () (bytevector-u8-ref target (ann 3 I64))))

(def invalid-byte (-> Unit)
     (lambda () (bytevector-u8-set! target (ann 0 I64) (ann 256 I64))))

(def readonly-write (-> Unit)
     (lambda ()
       (bytevector-u8-set! (mark (ann 1 I64) #u8(0)) (mark (ann 2 I64) (ann 0 I64)) (mark (ann 3 I64) (ann 42 I64)))))

(def observed-effects (-> I64)
     (lambda () (ref-get effects)))

(def readonly-empty-copy (-> Unit)
     (lambda () (bytevector-copy! #u8() (ann 0 I64) #u8() (ann 0 I64) (ann 0 I64))))

(def source-range (-> Unit)
     (lambda () (bytevector-copy! target (ann 0 I64) #u8(9 8) (ann 0 I64) (ann 3 I64))))

(def target-range (-> Unit)
     (lambda () (bytevector-copy! target (ann 2 I64) #u8(9 8) (ann 0 I64) (ann 2 I64))))

(def reversed-range (-> Unit)
     (lambda () (bytevector-copy! target (ann 0 I64) #u8(9 8) (ann 2 I64) (ann 1 I64))))

(def negative-range (-> Unit)
     (lambda () (bytevector-copy! target (ann 0 I64) #u8(9 8) (ann -1 I64) (ann 0 I64))))

(def empty-source-range (-> Unit)
     (lambda () (bytevector-copy! target (ann 0 I64) #u8() (ann 1 I64) (ann 1 I64))))

(def empty-target-range (-> Unit)
     (lambda () (bytevector-copy! target (ann 4 I64) #u8() (ann 0 I64) (ann 0 I64))))

(def negative-copy (-> I64)
     (lambda () (bytevector-length (bytevector-copy target (ann -1 I64) (ann 0 I64)))))

(def wrong-top (-> I64)
     (lambda () (bytevector-length (ann (ann (vector (ann 1 I64) (ann 2 I64)) Any) Bytevector))))

(def wrong-string (-> I64)
     (lambda () (string-length (ann (ann target Any) String))))

(def unchanged (-> Bool)
     (lambda ()
       (if (= (bytevector-u8-ref target (ann 0 I64)) (ann 1 I64))
           (if (= (bytevector-u8-ref target (ann 1 I64)) (ann 2 I64)) (= (bytevector-u8-ref target (ann 2 I64)) (ann 3 I64)) #f)
           #f)))
(ann 42 I64)
