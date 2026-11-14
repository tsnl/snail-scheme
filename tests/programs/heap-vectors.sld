(import
 (snail core base)
 (snail core io))

;; Vector elements occupy one Wasm slot: primitives stay unboxed and
;; aggregates are heap references. A Vector has a fixed runtime length.
(record Meters
  ((value I64)))

;; Copy elements may be shared by multiple array slots.
(define (fill-twice (item A)) (→ (Vector A)) (! e) (∀ (A e)) (⊨ (Copy A) (Drop e A))
  (make-vector 2 item))

;; An empty vector's element type comes from its signature.
(define (empty) (→ (Vector I64)) (vector))

(define (main) (→ Unit) (! mut output-port)
  (let ((lengths (make-vector 3 (new Meters (value 1)))))
    (vector-set! lengths 2 (new Meters (value 7)))
    (write-line (show (+ (● (vector-ref lengths 0) value) (● (vector-ref lengths 2) value)))))
  (let ((flags (make-vector 2 #f)) (names (make-vector 2 "a")) (maybe (make-vector 2 (None))))
    (vector-set! flags 1 #t)
    (vector-set! names 1 "b")
    (vector-set! maybe 0 (Some 5))
    (write-line (string-append (show (vector-ref flags 1)) " " (vector-ref names 1)))
    (match (vector-ref maybe 0)
      ((Some n) (write-line (show n)))
      ((None) (write-line "none"))))
  (write-line (show (vector-length (fill-twice 1.5))))
  (let ((numbers (list->vector (list 10 20 30 40 50))))
    (vector-set! numbers 1 21)
    (write-line (show (vector-length numbers)))
    (write-line (string-join (map show (vector->list numbers)) " "))
    (write-line (show (vector-ref numbers 4)))
    (write-line (show (vector-length numbers)))
    (write-line (show (vector-ref numbers 3))))
  (write-line (show (vector-length (empty))))
  (unit))
