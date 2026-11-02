(import
 (snail core base)
 (snail core io))

(struct Point
  ((x I64)
   (y I64)))

;; Values of different types travel together as Any and come back out.
(define values
  (list (type-convert 42 Any)
        (type-convert "text" Any)
        (type-convert (Point 3 4) Any)
        (type-convert 2.5 Any)))

(handle dyn-cast
    ((conversion-failed (lambda (error)
                          (write-line (string-append "caught: expected "
                                                     (string-join (CastError-expected error)
                                                                  ", "))))))
  (display (+ 1 (type-convert (list-ref values 0) I64)))
  (newline)
  (write-line (type-convert (list-ref values 1) String))
  (display (Point-y (type-convert (list-ref values 2) Point)))
  (newline)
  ;; Converting to the type a value already has does nothing, and a
  ;; round trip through Any is removed.
  (display (type-convert (type-convert 7 I64) I64))
  (newline)
  (display (type-convert (type-convert 8 Any) I64))
  (newline)
  ;; type-test asks what an Any holds, without trapping.
  (display (type-test (list-ref values 0) I64))
  (newline)
  (display (type-test (list-ref values 1) I64))
  (newline)
  (display (type-test (list-ref values 2) Point))
  (newline)
  (display (type-convert (list-ref values 3) I64))
  (newline))
