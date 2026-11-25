(import
 (snail core base)
 (snail core io))

(record Box
  ((value I64)))

(define (main (out OutputPort)) (→ Unit)
  (let* ((items (array-generate 9 (lambda (index) index))) (alias items))
    (write out (array->list alias)) (newline out)
    (array-set! alias 0 90)
    (write out (array-length items)) (newline out)
    (write out (array->list (array-append (subarray alias 0 2) (make-array 1 99)))) (newline out)
    (let ((copy (array-copy items)))
      (array-set! copy 0 10)
      (write out (array-ref items 0)) (newline out))
    (array-copy! alias 2 alias 0 3)
    (write out (array->list items)) (newline out))
  ;; Copying slots preserves the identity of the objects stored in them.
  (let* ((items (make-array 1 (new Box (value 3)))) (copy (array-copy items)))
    (set! (● (array-ref copy 0) value) 4)
    (write out (● (array-ref items 0) value)) (newline out))
  ;; String conversions copy: array mutation cannot change a String.
  (let* ((chars (string->array "abc")) (text (array->string chars)))
    (array-set! chars 0 #\x)
    (write-line out (string-append text (array->string chars)))
    (write-line out "abc"))
  (let* ((items #u8(1 2 3)) (alias items))
    (array-set! items 0 (ann 7 U8))
    (write out (array->list alias)) (newline out)
    (write out (array-length alias)) (newline out)))
