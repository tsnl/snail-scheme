(import
 (snail core base)
 (snail core io))

;; Array elements occupy one Wasm slot: primitives stay unboxed and
;; aggregates are heap references. An Array has a fixed runtime length.
(record Meters
  ((value I64)))

;; Copy elements may be shared by multiple array slots.
(define (fill-twice (item A)) (→ (Array A)) (∀ (A))
  (make-array 2 item))

;; An empty array's element type comes from its signature.
(define (empty) (→ (Array I64)) (array))

(define (main (mut Mut) (out OutputPort)) (→ Unit)
  (let ((lengths (make-array 3 (new Meters (value 1)))))
    (array-set! mut lengths 2 (new Meters (value 7)))
    (write-line out (show (+ (● (array-ref lengths 0) value) (● (array-ref lengths 2) value)))))
  (let ((flags (make-array 2 #f)) (names (make-array 2 "a")) (maybe (make-array 2 (None))))
    (array-set! mut flags 1 #t)
    (array-set! mut names 1 "b")
    (array-set! mut maybe 0 (Some 5))
    (write-line out (string-append (show (array-ref flags 1)) " " (array-ref names 1)))
    (match (array-ref maybe 0)
      ((Some n) (write-line out (show n)))
      ((None) (write-line out "none"))))
  (write-line out (show (array-length (fill-twice 1.5))))
  (let ((numbers (list->array (list 10 20 30 40 50))))
    (array-set! mut numbers 1 21)
    (write-line out (show (array-length numbers)))
    (write-line out (string-join (map show (array->list numbers)) " "))
    (write-line out (show (array-ref numbers 4)))
    (write-line out (show (array-length numbers)))
    (write-line out (show (array-ref numbers 3))))
  (write-line out (show (array-length (empty))))
  (unit))
