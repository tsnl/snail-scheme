(import
 (snail core base)
 (snail core io))

(struct Box
  ((value I64)))

(define (main) (→ Unit) (! mut output-port)
  (let* ((items (vector-generate 9 (lambda (index) index))) (alias items))
    (write (vector->list alias)) (newline)
    (vector-set! alias 0 90)
    (write (vector-length items)) (newline)
    (write (vector->list (vector-append (subvector alias 0 2) (make-vector 1 99)))) (newline)
    (let ((copy (vector-copy items)))
      (vector-set! copy 0 10)
      (write (vector-ref items 0)) (newline))
    (vector-copy! alias 2 alias 0 3)
    (write (vector->list items)) (newline))
  ;; Copying slots preserves the identity of the objects stored in them.
  (let* ((items (make-vector 1 (Box 3))) (copy (vector-copy items)))
    (set! (● (vector-ref copy 0) value) 4)
    (write (● (vector-ref items 0) value)) (newline))
  ;; String conversions copy: vector mutation cannot change a String.
  (let* ((chars (string->vector "abc")) (text (vector->string chars)))
    (vector-set! chars 0 #\x)
    (write-line (string-append text (vector->string chars)))
    (write-line "abc"))
  (let* ((items #u8(1 2 3)) (alias items))
    (vector-set! items 0 (ann 7 U8))
    (write (vector->list alias)) (newline)
    (write (vector-length alias)) (newline)))
