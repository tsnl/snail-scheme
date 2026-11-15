(import
 (snail core base)
 (snail core io))

(record Box
  ((value I64)))

(define (main) (→ Unit) (! mut output-port)
  (let* ((items (array-generate 9 (lambda (index) index))) (alias items))
    (write (array->list alias)) (newline)
    (array-set! alias 0 90)
    (write (array-length items)) (newline)
    (write (array->list (array-append (subarray alias 0 2) (make-array 1 99)))) (newline)
    (let ((copy (array-copy items)))
      (array-set! copy 0 10)
      (write (array-ref items 0)) (newline))
    (array-copy! alias 2 alias 0 3)
    (write (array->list items)) (newline))
  ;; Copying slots preserves the identity of the objects stored in them.
  (let* ((items (make-array 1 (new Box (value 3)))) (copy (array-copy items)))
    (set! (● (array-ref copy 0) value) 4)
    (write (● (array-ref items 0) value)) (newline))
  ;; String conversions copy: array mutation cannot change a String.
  (let* ((chars (string->array "abc")) (text (array->string chars)))
    (array-set! chars 0 #\x)
    (write-line (string-append text (array->string chars)))
    (write-line "abc"))
  (let* ((items #u8(1 2 3)) (alias items))
    (array-set! items 0 (ann 7 U8))
    (write (array->list alias)) (newline)
    (write (array-length alias)) (newline)))
