(import
 (snail core base)
 (snail core io))

;; An array's elements are unboxed: each is one Wasm slot, a scalar, a
;; reference or a struct of one unboxed field. A MutVector grows at its end
;; over such an array.
(struct Meters
  ((value I64)))

(let ((lengths (make-array 3 (Meters 1))))
  (array-set! lengths 2 (Meters 7))
  (write-line (show (+ (::value (array-ref lengths 0)) (::value (array-ref lengths 2))))))

(let ((flags (make-array 2 #f)) (names (make-array 2 "a")) (maybe (make-array 2 (None))))
  (array-set! flags 1 #t)
  (array-set! names 1 "b")
  (array-set! maybe 0 (Some 5))
  (write-line (string-append (show (array-ref flags 1)) " " (array-ref names 1)))
  (match (array-ref maybe 0)
    ((Some n) (write-line (show n)))
    ((None) (write-line "none"))))

;; A generic function over arrays requires Unboxed of its element.
(: fill-twice (All (A) (requires (Copy A) (Unboxed A)) (-> A (Array A) ! mut)))
(define (fill-twice item)
  (make-array 2 item))

(write-line (show (array-length (fill-twice 1.5))))

(let ((numbers (mut-vector)))
  (mut-vector-push! numbers 10)
  (mut-vector-push! numbers 20)
  (mut-vector-push! numbers 30)
  (mut-vector-push! numbers 40)
  (mut-vector-push! numbers 50)
  (mut-vector-set! numbers 1 21)
  (write-line (show (mut-vector-length numbers)))
  (write-line (string-join (map show (vector->list (mut-vector->vector numbers))) " "))
  (match (mut-vector-pop! numbers)
    ((Some last) (write-line (show last)))
    ((None) (write-line "empty")))
  (write-line (show (mut-vector-length numbers)))
  (write-line (show (mut-vector-ref numbers 3))))

;; An empty vector's element type comes from its signature.
(: empty (MutVector I64))
(define empty (mut-vector))

(match (mut-vector-pop! empty)
  ((Some last) (write-line (show last)))
  ((None) (write-line "empty")))
(write-line (show (vector-length (mut-vector->vector empty))))
