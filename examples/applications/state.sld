;; Immutable application values and an owned, portable snapshot codec.
(define-library (examples application-state)
  (export answer)
  (import
   (scheme base)
   (scheme immutable)
   (only (lofi core) ann -> I32 I64)
   (only (lofi base) unreachable))
  (begin
    (define-immutable-record Stock stock
      (ore I32 stock-ore stock-ore-set))
    (define (encode-stock value)
      (let ((words (ann (make-vector (ann 2 I64) 0) (Vector I32))))
        (vector-set! words (ann 0 I64) 1)
        (vector-set! words (ann 1 I64) (stock-ore value))
        words))
    (define (decode-stock words)
      (if (= (vector-ref words (ann 0 I64)) 1)
          (stock (vector-ref words (ann 1 I64)))
          (unreachable)))
    (define answer
      (ann (lambda ()
             (let* ((before (stock 40))
                    (after (stock-ore-set before (+ (stock-ore before) 2))))
               (if (= (stock-ore before) 40)
                   (stock-ore (decode-stock (encode-stock after))) 0)))
           (-> I32)))))
