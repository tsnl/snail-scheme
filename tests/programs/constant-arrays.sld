;; Constant arrays: tables of scalar literals built once and shared, read
;; and copied as arrays are, and never written. A table is data of any
;; size; a float table is a table of the floats' bits.
(import
 (snail core base)
 (snail core io))

(define (bytes) (→ (ConstantArray U8)) (constant-array U8 (0 1 127 255)))

(define (words) (→ (ConstantArray I32)) (constant-array I32 (-2147483648 -1 0 2147483647)))

(define (longs) (→ (ConstantArray I64))
  (constant-array I64 (-9223372036854775808 -4294967297 -1 4294967296 9223372036854775807)))

(define (floats) (→ (ConstantArray I64))
  (constant-array I64 (4602678819172646912 -4611123068473966592 4613937818241073152)))

(define (flags) (→ (ConstantArray Bool)) (constant-array Bool (#t #f #t)))

(define (letters) (→ (ConstantArray Char)) (constant-array Char (#\a #\λ #\z)))

(define (all (table (ConstantArray A)) (text (Fn A → String))) (→ String) (∀ (A))
  (string-join (map (lambda (index) (text (constant-array-ref table index)))
                    (iota (constant-array-length table)))
               " "))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (write-line out (all (bytes) (lambda (byte) (show (u8->i32 byte)))))
  (write-line out (all (words) show))
  (write-line out (all (longs) show))
  (write-line out (all (floats) (lambda (bits) (show (bits->f64 bits)))))
  (write-line out (all (flags) (lambda (flag) (if flag "yes" "no"))))
  (write-line out (all (letters) (lambda (letter) (list->string (list letter)))))
  (let ((copy (constant-array->array (bytes))))
    (array-set! copy 0 (i32->u8 42))
    (write-line out (string-append (show (u8->i32 (array-ref copy 0)))
                                   " "
                                   (show (u8->i32 (constant-array-ref (bytes) 0)))))))
